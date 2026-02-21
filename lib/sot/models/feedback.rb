module SOT
  class Feedback < Sequel::Model(:_feedback)
    plugin :timestamps, create_only: true
    plugin :validation_helpers

    many_to_one :user, class: 'SOT::User'
    many_to_one :schema, class: 'SOT::Schema'

    def validate
      super
      validates_presence [:user_id, :context, :confusion]
    end
  end
end
