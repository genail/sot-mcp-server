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

    def self.create(schema:, data:, state: nil, user:)
      validate_data!(schema, data)
      state = resolve_initial_state(schema, state)
      validate_state!(schema, state) if state

      record = nil
      DB.transaction(mode: :immediate) do
        record = Record.create(
          schema_id: schema.id,
          data: JSON.generate(data),
          state: state,
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

    def self.update(record:, data: nil, state: nil, preconditions: {}, user:, replace_data: false)
      schema = record.schema

      raise ValidationError, "Cannot set state on a stateless entity type" if state && !schema.stateful?
      raise ValidationError, "data must be a Hash" if data && !data.is_a?(Hash)
      validate_state!(schema, state) if state

      DB.transaction(mode: :immediate) do
        # Re-fetch inside transaction for atomicity (IMMEDIATE mode ensures write lock is held)
        fresh = Record.where(id: record.id).first
        raise ValidationError, "Record not found (may have been deleted)" unless fresh

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
          validate_data!(schema, resolved_data)
          updates[:data] = JSON.generate(resolved_data)
        end
        updates[:state] = state if state
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

    def self.delete(record:, preconditions: {}, user:)
      schema = record.schema

      DB.transaction(mode: :immediate) do
        # Re-fetch inside transaction for atomicity (IMMEDIATE mode ensures write lock is held)
        fresh = Record.where(id: record.id).first
        raise ValidationError, "Record not found (may have been deleted)" unless fresh

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
          raise ValidationError, "Cannot set state on a stateless entity type" if state
          nil
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
