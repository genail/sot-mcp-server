module SOT
  module Tools
    module User
      class CallWebhook < MCP::Tool
        tool_name 'sot_call_webhook'

        description <<~DESC
          Call a webhook by name, providing values for its variables.

          The server renders the webhook's payload template with the provided variable values,
          makes the HTTP call, and returns success/failure with the status code.
          Use sot_list_webhooks first to see available webhooks and their required variables.
        DESC

        input_schema(
          properties: {
            name: {
              type: 'string',
              description: 'The webhook name'
            },
            variable_values: {
              type: 'object',
              description: 'Key-value pairs for template variables',
              additionalProperties: { type: 'string' }
            }
          },
          required: %w[name variable_values]
        )

        def self.call(server_context:, **params)
          user = server_context[:user]
          webhook = SOT::Webhook.first(name: params[:name])

          if webhook.nil? || !SOT::WebhookService.can_call?(user, webhook)
            return error_response("Webhook '#{params[:name]}' not found.")
          end

          result = SOT::WebhookService.call_webhook(
            webhook: webhook,
            user: user,
            variable_values: params[:variable_values] || {}
          )

          if result[:success]
            MCP::Tool::Response.new([{
              type: 'text',
              text: "Webhook '#{params[:name]}' called successfully (HTTP #{result[:status_code]})."
            }])
          else
            status = result[:status_code] ? " (HTTP #{result[:status_code]})" : ''
            error_msg = result[:error] ? ": #{result[:error]}" : ''
            error_response("Webhook '#{params[:name]}' call failed#{status}#{error_msg}")
          end
        rescue SOT::WebhookService::ValidationError => e
          error_response(e.message)
        end

        private

        def self.error_response(message)
          MCP::Tool::Response.new([{ type: 'text', text: message }], error: true)
        end
      end
    end
  end
end
