module SOT
  module Tools
    module User
      class ListWebhooks < MCP::Tool
        tool_name 'sot_list_webhooks'

        description <<~DESC
          List available webhooks that you can call.

          Returns webhook name, description, and variables (with descriptions) for each webhook
          your role is allowed to call. Use sot_call_webhook to invoke a webhook by name.
        DESC

        input_schema(properties: {})

        def self.call(server_context:, **_params)
          user = server_context[:user]

          webhooks = SOT::Webhook.order(:name).all.select do |wh|
            SOT::WebhookService.can_call?(user, wh)
          end

          if webhooks.empty?
            return MCP::Tool::Response.new([{ type: 'text', text: 'No webhooks available.' }])
          end

          lines = webhooks.map do |wh|
            vars = wh.parsed_variables
            var_lines = vars.map { |v| "    - #{v['name']}: #{v['description']}" }
            var_section = vars.empty? ? '  Variables: none' : "  Variables:\n#{var_lines.join("\n")}"
            "- #{wh.name}: #{wh.description}\n#{var_section}"
          end

          MCP::Tool::Response.new([{ type: 'text', text: "Available webhooks:\n#{lines.join("\n\n")}" }])
        end
      end
    end
  end
end
