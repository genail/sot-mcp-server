module SOT
  class WebhookLog < Sequel::Model(:_webhook_logs)
    plugin :timestamps, create: :created_at, update_on_create: false

    many_to_one :webhook, class: 'SOT::Webhook'
    many_to_one :user, class: 'SOT::User'

    def parsed_variable_values
      variable_values ? JSON.parse(variable_values) : {}
    end
  end
end
