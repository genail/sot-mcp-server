module SOT
  module Tools
    module Admin
      class WebhookLogs < MCP::Tool
        tool_name 'sot_admin_webhook_logs'

        description <<~DESC
          View webhook execution logs. Shows who called what webhook, when,
          with what variable values, and what the response was.

          Optionally filter by webhook_name. Results are ordered most recent first.
        DESC

        input_schema(
          properties: {
            webhook_name: {
              type: 'string',
              description: 'Filter logs by webhook name (optional)'
            },
            limit: {
              type: 'integer',
              description: 'Maximum number of logs to return (default: 50)'
            }
          }
        )

        def self.call(server_context:, **params)
          dataset = SOT::WebhookLog.order(Sequel.desc(:created_at))

          if params[:webhook_name]
            webhook = SOT::Webhook.first(name: params[:webhook_name])
            return error("Webhook '#{params[:webhook_name]}' not found.") unless webhook
            dataset = dataset.where(webhook_id: webhook.id)
          end

          limit = params[:limit] || 50
          logs = dataset.limit(limit).all

          if logs.empty?
            return MCP::Tool::Response.new([{ type: 'text', text: 'No webhook logs found.' }])
          end

          lines = logs.map do |log|
            webhook = log.webhook
            user = log.user
            status = log.success ? "SUCCESS" : "FAILED"
            status_code = log.status_code ? " (HTTP #{log.status_code})" : ''
            error_info = log.error_message ? "\n  Error: #{log.error_message}" : ''
            response_info = log.response_body ? "\n  Response: #{log.response_body}" : ''

            "- [#{log.created_at}] #{webhook.name} by #{user.name}: #{status}#{status_code}" \
              "\n  Variables: #{log.variable_values || '{}'}" \
              "#{response_info}#{error_info}"
          end

          MCP::Tool::Response.new([{ type: 'text', text: "Webhook logs:\n#{lines.join("\n\n")}" }])
        end

        private

        def self.error(message)
          MCP::Tool::Response.new([{ type: 'text', text: message }], error: true)
        end
      end
    end
  end
end
