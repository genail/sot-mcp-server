module SOT
  class MutationService
    class PreconditionFailed < StandardError
      attr_reader :expected, :actual, :record

      def initialize(message, expected:, actual:, record:)
        @expected = expected
        @actual = actual
        @record = record
        super(message)
      end
    end

    class ValidationError < StandardError; end

    class VersionConflict < StandardError
      attr_reader :expected_version, :actual_version, :record

      def initialize(expected_version:, actual_version:, record:)
        @expected_version = expected_version
        @actual_version = actual_version
        @record = record
        super("Version conflict: you provided version #{expected_version} but the record is now at version #{actual_version}. Re-fetch the record with sot_query to see the latest changes, then retry.")
      end
    end

    def self.create(schema:, data:, state: nil, user:)
      data = data.transform_keys(&:to_s) if data.is_a?(Hash)
      validate_data!(schema, data)
      data = coerce_data!(schema, data)
      state = resolve_initial_state(schema, state)
      validate_state!(schema, state) if state

      record = nil
      DB.transaction(mode: :immediate) do
        record = Record.create(
          schema_id: schema.id,
          data: JSON.generate(data),
          state: state,
          version: 1,
          created_by: user.id,
          updated_by: user.id
        )

        ActivityLog.create(
          user_id: user.id,
          record_id: record.id,
          schema_id: schema.id,
          action: 'create',
          changes: JSON.generate({
            before: nil,
            after: { data: data, state: state }
          })
        )
      end

      record
    end

    def self.update(record:, data: nil, state: nil, preconditions: {}, user:, replace_data: false, append_data: nil, expected_version: nil)
      schema = record.schema

      raise ValidationError, "Cannot set state on a stateless table" if state && !schema.stateful?
      raise ValidationError, "data must be a Hash" if data && !data.is_a?(Hash)
      raise ValidationError, "append_data must be a Hash" if append_data && !append_data.is_a?(Hash)
      data = data.transform_keys(&:to_s) if data
      append_data = append_data.transform_keys(&:to_s) if append_data
      validate_append_data!(schema, append_data) if append_data
      data = coerce_data!(schema, data) if data
      validate_state!(schema, state) if state

      if data && append_data
        overlap = data.keys.map(&:to_s) & append_data.keys.map(&:to_s)
        unless overlap.empty?
          raise ValidationError, "Fields cannot appear in both data and append_data: #{overlap.join(', ')}"
        end
      end

      # Determine if this is an append-only operation (no version check required)
      append_only = append_data && !data && !state && !replace_data

      unless append_only
        raise ValidationError, "version is required for update (omit only for append-only operations)" if expected_version.nil?
      end

      DB.transaction(mode: :immediate) do
        # Re-fetch inside transaction for atomicity (IMMEDIATE mode ensures write lock is held)
        fresh = Record.where(id: record.id).first
        raise ValidationError, "Record not found (may have been deleted)" unless fresh

        # Version check (skip for append-only)
        unless append_only
          actual_version = fresh.current_version
          unless actual_version == expected_version
            raise VersionConflict.new(
              expected_version: expected_version,
              actual_version: actual_version,
              record: fresh
            )
          end
        end

        check_preconditions!(fresh, preconditions, schema)

        before_data = fresh.parsed_data
        before_state = fresh.state

        resolved_data = nil
        updates = { updated_by: user.id }
        if data
          resolved_data = if replace_data
                            data
                          else
                            m = before_data.merge(data)
                            m.reject! { |_, v| v.nil? }
                            m
                          end
        end

        if append_data
          resolved_data = (resolved_data || before_data).dup
          append_data.each do |field, value|
            existing = resolved_data[field.to_s]
            resolved_data[field.to_s] = existing ? "#{existing}#{value}" : value.to_s
          end
        end

        if resolved_data
          validate_data!(schema, resolved_data)
          updates[:data] = JSON.generate(resolved_data)
        end
        updates[:state] = state if state
        updates[:version] = fresh.current_version + 1
        fresh.update(updates)

        after_data = resolved_data || before_data
        after_state = state || before_state

        ActivityLog.create(
          user_id: user.id,
          record_id: fresh.id,
          schema_id: schema.id,
          action: 'update',
          changes: JSON.generate({
            before: { data: before_data, state: before_state },
            after: { data: after_data, state: after_state }
          })
        )

        fresh
      end
    end

    def self.delete(record:, preconditions: {}, user:, expected_version: nil)
      schema = record.schema

      raise ValidationError, "version is required for delete" if expected_version.nil?

      DB.transaction(mode: :immediate) do
        # Re-fetch inside transaction for atomicity (IMMEDIATE mode ensures write lock is held)
        fresh = Record.where(id: record.id).first
        raise ValidationError, "Record not found (may have been deleted)" unless fresh

        actual_version = fresh.current_version
        unless actual_version == expected_version
          raise VersionConflict.new(
            expected_version: expected_version,
            actual_version: actual_version,
            record: fresh
          )
        end

        check_preconditions!(fresh, preconditions, schema)

        before_data = fresh.parsed_data
        before_state = fresh.state

        ActivityLog.create(
          user_id: user.id,
          record_id: fresh.id,
          schema_id: schema.id,
          action: 'delete',
          changes: JSON.generate({
            before: { data: before_data, state: before_state },
            after: nil
          })
        )

        fresh.destroy
      end

      true
    end

    class << self
      private

      def coerce_data!(schema, data)
        SOT::TypeCoercion.coerce_data(data, schema)
      rescue SOT::TypeCoercion::CoercionError => e
        raise ValidationError, e.message
      end

      def validate_data!(schema, data)
        raise ValidationError, "data must be a Hash" unless data.is_a?(Hash)

        missing = schema.required_field_names - data.keys.map(&:to_s)
        unless missing.empty?
          raise ValidationError, "Missing required fields: #{missing.join(', ')}"
        end

        unknown = data.keys.map(&:to_s) - schema.all_field_names
        unless unknown.empty?
          raise ValidationError, "Unknown fields: #{unknown.join(', ')}"
        end
      end

      def validate_state!(schema, state)
        return unless state
        return unless schema.stateful?

        unless schema.valid_state?(state)
          valid = schema.parsed_states.map { |s| s['name'] }.join(', ')
          raise ValidationError, "Invalid state '#{state}'. Valid states: #{valid}"
        end
      end

      def resolve_initial_state(schema, state)
        if schema.stateful?
          state || schema.default_state
        else
          raise ValidationError, "Cannot set state on a stateless table" if state
          nil
        end
      end

      APPENDABLE_TYPES = %w[string text].freeze

      def validate_append_data!(schema, append_data)
        raise ValidationError, "append_data must be a Hash" unless append_data.is_a?(Hash)

        fields_by_name = schema.parsed_fields.each_with_object({}) { |f, h| h[f['name']] = f }
        append_data.each_key do |field_name|
          name = field_name.to_s
          field_def = fields_by_name[name]
          unless field_def
            raise ValidationError, "Unknown field in append_data: #{name}"
          end
          unless APPENDABLE_TYPES.include?(field_def['type'])
            raise ValidationError, "Cannot append to field '#{name}' of type '#{field_def['type']}'. Only #{APPENDABLE_TYPES.join(', ')} fields support append."
          end
        end
      end

      def check_preconditions!(record, preconditions, schema)
        return if preconditions.nil? || preconditions.empty?

        if preconditions.key?('state') || preconditions.key?(:state)
          expected_state = preconditions['state'] || preconditions[:state]
          actual_state = record.state

          unless actual_state == expected_state
            raise PreconditionFailed.new(
              "Precondition failed: expected state '#{expected_state}' but found '#{actual_state}'",
              expected: { state: expected_state },
              actual: { state: actual_state },
              record: record
            )
          end
        end

        record_data = record.parsed_data
        preconditions.each do |key, expected_value|
          key_s = key.to_s
          next if key_s == 'state'

          actual_value = record_data[key_s]
          unless actual_value == expected_value
            raise PreconditionFailed.new(
              "Precondition failed: expected #{key_s}='#{expected_value}' but found '#{actual_value}'",
              expected: { key_s => expected_value },
              actual: { key_s => actual_value },
              record: record
            )
          end
        end
      end
    end
  end
end
