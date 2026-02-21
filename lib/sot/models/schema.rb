require 'json'

module SOT
  class Schema < Sequel::Model(:_schemas)
    plugin :timestamps, update_on_create: true
    plugin :validation_helpers

    one_to_many :records, class: 'SOT::Record'
    one_to_many :activity_logs, class: 'SOT::ActivityLog'

    def validate
      super
      validates_presence [:namespace, :name, :fields]
      validates_unique [:namespace, :name]
      validates_format(/\A[a-z][a-z0-9_]*\z/, :namespace, message: 'must be lowercase alphanumeric with underscores') if namespace
      validates_format(/\A[a-z][a-z0-9_]*\z/, :name, message: 'must be lowercase alphanumeric with underscores') if name
    end

    def full_name
      "#{namespace}.#{name}"
    end

    def parsed_fields
      JSON.parse(fields)
    end

    def parsed_states
      states ? JSON.parse(states) : nil
    end

    def stateful?
      !states.nil?
    end

    def valid_state?(state_name)
      return true unless stateful?

      parsed_states.any? { |s| s['name'] == state_name }
    end

    def required_field_names
      parsed_fields.select { |f| f['required'] }.map { |f| f['name'] }
    end

    def all_field_names
      parsed_fields.map { |f| f['name'] }
    end

    def default_state
      return nil unless stateful?

      parsed_states.first&.dig('name')
    end
  end
end
