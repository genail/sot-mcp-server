module SOT
  class SchemaService
    VALID_FIELD_TYPES = %w[string integer float boolean text date datetime user].freeze

    def self.validate_fields!(fields_array)
      raise ArgumentError, "fields must be an array" unless fields_array.is_a?(Array)
      raise ArgumentError, "fields cannot be empty" if fields_array.empty?

      fields_array.each_with_index do |f, i|
        f = stringify_keys(f)
        raise ArgumentError, "field #{i}: must have 'name'" unless f['name'].is_a?(String) && !f['name'].empty?
        raise ArgumentError, "field #{i}: must have 'type'" unless f['type'].is_a?(String) && !f['type'].empty?
        raise ArgumentError, "field #{i}: type '#{f['type']}' is invalid. Must be one of: #{VALID_FIELD_TYPES.join(', ')}" unless VALID_FIELD_TYPES.include?(f['type'])
      end
    end

    def self.validate_states!(states_array)
      return if states_array.nil?

      raise ArgumentError, "states must be an array" unless states_array.is_a?(Array)
      raise ArgumentError, "states cannot be empty if provided" if states_array.empty?

      states_array.each_with_index do |s, i|
        s = stringify_keys(s)
        raise ArgumentError, "state #{i}: must have 'name'" unless s['name'].is_a?(String) && !s['name'].empty?
      end
    end

    ACL_COLUMNS = %i[read_roles create_roles update_roles delete_roles].freeze

    def self.create(namespace:, name:, description: nil, fields:, states: nil, **acl)
      validate_fields!(fields)
      validate_states!(states)
      validate_acl!(acl)

      attrs = {
        namespace: namespace,
        name: name,
        description: description,
        fields: JSON.generate(normalize_hash_array(fields)),
        states: states ? JSON.generate(normalize_hash_array(states)) : nil
      }
      ACL_COLUMNS.each do |col|
        attrs[col] = JSON.generate(acl[col]) if acl.key?(col)
      end

      Schema.create(attrs)
    end

    def self.update(schema, confirm_delete_fields: [], **attrs)
      validate_fields!(attrs[:fields]) if attrs.key?(:fields)
      validate_states!(attrs[:states]) if attrs.key?(:states)
      validate_acl!(attrs)

      field_changes = nil

      if attrs.key?(:fields) || confirm_delete_fields.any?
        new_fields = attrs.key?(:fields) ? normalize_hash_array(attrs[:fields]) : []
        field_changes = merge_fields(schema, new_fields, confirm_delete_fields)
        merged = field_changes[:merged_fields]
        raise ArgumentError, "fields cannot be empty" if merged.empty?
        validate_type_changes!(schema, merged)
        attrs[:fields] = merged
      end

      updates = {}
      updates[:namespace] = attrs[:namespace] if attrs.key?(:namespace)
      updates[:name] = attrs[:name] if attrs.key?(:name)
      updates[:description] = attrs[:description] if attrs.key?(:description)
      updates[:fields] = JSON.generate(attrs[:fields]) if attrs.key?(:fields)
      updates[:states] = (attrs[:states] ? JSON.generate(normalize_hash_array(attrs[:states])) : nil) if attrs.key?(:states)
      ACL_COLUMNS.each do |col|
        updates[col] = JSON.generate(attrs[col]) if attrs.key?(col)
      end

      schema.update(updates) unless updates.empty?
      { schema: schema, field_changes: field_changes }
    end

    def self.reorder_fields(schema, field_order)
      raise ArgumentError, "field_order must be an array" unless field_order.is_a?(Array)
      raise ArgumentError, "Duplicate fields in order list" if field_order.length != field_order.uniq.length

      existing_names = schema.parsed_fields.map { |f| f['name'] }

      missing = existing_names - field_order
      extra = field_order - existing_names
      raise ArgumentError, "Missing fields in order list: #{missing.join(', ')}" if missing.any?
      raise ArgumentError, "Unknown fields in order list: #{extra.join(', ')}" if extra.any?

      if existing_names == field_order
        return { changed: false, schema: schema }
      end

      fields_by_name = schema.parsed_fields.each_with_object({}) { |f, h| h[f['name']] = f }
      reordered = field_order.map { |name| fields_by_name[name] }
      schema.update(fields: JSON.generate(reordered))
      { changed: true, schema: schema, old_order: existing_names, new_order: field_order }
    end

    def self.delete(schema)
      schema.destroy
    end

    def self.find_by_name(namespace, name)
      Schema.first(namespace: namespace, name: name)
    end

    def self.resolve(entity_name)
      return nil if entity_name.nil? || entity_name.empty?

      if entity_name.include?('.')
        ns, nm = entity_name.split('.', 2)
        find_by_name(ns, nm)
      else
        Schema.first(name: entity_name)
      end
    end

    def self.resolve_many(entity_names)
      entity_names.each_with_object({}) { |name, hash| hash[name] = resolve(name) }
    end

    def self.list(namespace: nil)
      dataset = Schema.order(:namespace, :name)
      dataset = dataset.where(namespace: namespace) if namespace
      dataset.all
    end

    private

    def self.merge_fields(schema, new_fields, confirm_delete_fields)
      old_fields = schema.parsed_fields
      old_by_name = old_fields.each_with_object({}) { |f, h| h[f['name']] = f }
      new_by_name = new_fields.each_with_object({}) { |f, h| h[f['name']] = f }

      delete_names = Array(confirm_delete_fields)
      if delete_names.any?
        unknown = delete_names - old_by_name.keys
        raise ArgumentError, "Cannot delete unknown fields: #{unknown.join(', ')}" if unknown.any?
      end

      added = []
      updated = []
      removed = delete_names.map { |name| old_by_name[name] }

      merged = old_fields.reject { |f| delete_names.include?(f['name']) }.map do |old_f|
        if new_by_name.key?(old_f['name'])
          new_f = new_by_name[old_f['name']]
          changes = detect_field_changes(old_f, new_f)
          updated << { name: old_f['name'], changes: changes } if changes.any?
          old_f.merge(new_f)
        else
          old_f
        end
      end

      new_fields.each do |nf|
        unless old_by_name.key?(nf['name'])
          added << nf
          merged << nf
        end
      end

      { merged_fields: merged, added: added, updated: updated, removed: removed }
    end

    def self.detect_field_changes(old_f, new_f)
      changes = {}
      (old_f.keys | new_f.keys).each do |key|
        next if key == 'name'
        changes[key] = [old_f[key], new_f[key]] if old_f[key] != new_f[key]
      end
      changes
    end

    def self.validate_acl!(attrs)
      valid_role_names = Role.select_map(:name)

      ACL_COLUMNS.each do |col|
        next unless attrs.key?(col)
        roles = attrs[col]
        raise ArgumentError, "#{col} must be an array" unless roles.is_a?(Array)

        unknown = roles - valid_role_names
        unless unknown.empty?
          raise ArgumentError, "Unknown role(s) in #{col}: #{unknown.join(', ')}"
        end
      end
    end

    def self.validate_type_changes!(schema, new_fields)
      old_fields = schema.parsed_fields
      old_types = old_fields.each_with_object({}) { |f, h| h[f['name']] = f['type'] }
      new_types = new_fields.each_with_object({}) { |f, h| h[f['name']] = f['type'] }

      changed = new_types.select { |name, type| old_types[name] && old_types[name] != type }
      return if changed.empty?

      records = Record.where(schema_id: schema.id).all
      return if records.empty?

      violations = []

      records.each do |record|
        data = record.parsed_data
        changed.each do |field_name, new_type|
          value = data[field_name]
          next if value.nil?

          begin
            SOT::TypeCoercion.coerce(value, new_type, field_name: field_name)
          rescue SOT::TypeCoercion::CoercionError => e
            violations << { record_id: record.id, field: field_name, value: value, error: e.message }
          end
        end
      end

      return if violations.empty?

      details = violations.map { |v| "  Record ##{v[:record_id]}, field '#{v[:field]}': #{v[:error]}" }
      raise ArgumentError,
        "Cannot change field types: #{violations.size} value(s) incompatible with new types.\n#{details.join("\n")}"
    end

    def self.stringify_keys(hash)
      return hash unless hash.is_a?(Hash)
      hash.transform_keys(&:to_s)
    end

    def self.normalize_hash_array(array)
      return array unless array.is_a?(Array)
      array.map { |item| stringify_keys(item) }
    end
  end
end
