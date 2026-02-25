module SOT
  class SchemaService
    VALID_FIELD_TYPES = %w[string integer float boolean text datetime user].freeze

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

    def self.create(namespace:, name:, description: nil, fields:, states: nil)
      validate_fields!(fields)
      validate_states!(states)

      Schema.create(
        namespace: namespace,
        name: name,
        description: description,
        fields: JSON.generate(normalize_hash_array(fields)),
        states: states ? JSON.generate(normalize_hash_array(states)) : nil
      )
    end

    def self.update(schema, **attrs)
      validate_fields!(attrs[:fields]) if attrs.key?(:fields)
      validate_states!(attrs[:states]) if attrs.key?(:states)

      if attrs.key?(:fields)
        validate_type_changes!(schema, normalize_hash_array(attrs[:fields]))
      end

      updates = {}
      updates[:namespace] = attrs[:namespace] if attrs.key?(:namespace)
      updates[:name] = attrs[:name] if attrs.key?(:name)
      updates[:description] = attrs[:description] if attrs.key?(:description)
      updates[:fields] = JSON.generate(normalize_hash_array(attrs[:fields])) if attrs.key?(:fields)
      updates[:states] = (attrs[:states] ? JSON.generate(normalize_hash_array(attrs[:states])) : nil) if attrs.key?(:states)

      schema.update(updates) unless updates.empty?
      schema
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

    def self.list(namespace: nil)
      dataset = Schema.order(:namespace, :name)
      dataset = dataset.where(namespace: namespace) if namespace
      dataset.all
    end

    private

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
