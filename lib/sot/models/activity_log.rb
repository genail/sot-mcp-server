require 'json'

module SOT
  class ActivityLog < Sequel::Model(:_activity_log)
    plugin :timestamps, create_only: true
    plugin :validation_helpers

    many_to_one :user, class: 'SOT::User'
    many_to_one :record, class: 'SOT::Record'
    many_to_one :schema, class: 'SOT::Schema'

    VALID_ACTIONS = %w[create update delete].freeze

    def validate
      super
      validates_presence [:user_id, :schema_id, :action, :changes]
      validates_includes VALID_ACTIONS, :action
    end

    def parsed_changes
      JSON.parse(changes)
    end
  end
end
