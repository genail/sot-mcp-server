module SOT
  module Tools
    module Admin
      class ManageWebhooks < MCP::Tool
        tool_name 'sot_admin_manage_webhooks'

        description <<~DESC
          Manage webhooks — callable HTTP endpoints that agents can trigger.

          Actions:
          - create: Create a new webhook. Requires name, url, payload_template.
          - list: List all webhooks with full details (including URLs and headers).
          - update: Update a webhook. Requires name to identify which webhook.
          - delete: Delete a webhook. Requires name.

          Template uses {{variable_name}} placeholders. Variables must be defined with
          name and description. The server validates that template placeholders match
          the variables list.
        DESC

        input_schema(
          properties: {
            action: {
              type: 'string',
              enum: %w[create list update delete],
              description: 'The management action'
            },
            name: { type: 'string', description: 'Webhook name (unique identifier)' },
            description: { type: 'string', description: 'When this webhook should be used' },
            url: { type: 'string', description: 'Target URL' },
            http_method: {
              type: 'string',
              enum: %w[GET POST PUT PATCH DELETE],
              description: 'HTTP method (default: POST)'
            },
            headers: {
              type: 'object',
              description: 'HTTP headers to send',
              additionalProperties: { type: 'string' }
            },
            payload_template: {
              type: 'string',
              description: 'JSON template with {{variable}} placeholders'
            },
            variables: {
              type: 'array',
              description: 'Variable definitions with name and description',
              items: {
                type: 'object',
                properties: {
                  name: { type: 'string' },
                  description: { type: 'string' }
                },
                required: %w[name description]
              }
            },
            allowed_roles: {
              type: 'array',
              description: 'Role names allowed to call this webhook (empty = admin only)',
              items: { type: 'string' }
            }
          },
          required: ['action']
        )

        def self.call(server_context:, **params)
          case params[:action]
          when 'create' then handle_create(params)
          when 'list' then handle_list
          when 'update' then handle_update(params)
          when 'delete' then handle_delete(params)
          else
            error("Unknown action '#{params[:action]}'.")
          end
        end

        private

        def self.handle_create(params)
          return error("'name' is required.") unless params[:name]
          return error("'url' is required.") unless params[:url]
          return error("'payload_template' is required.") unless params[:payload_template]

          webhook = SOT::Webhook.new(
            name: params[:name],
            description: params[:description],
            url: params[:url],
            http_method: params[:http_method] || 'POST',
            headers: params[:headers] ? JSON.generate(params[:headers]) : nil,
            payload_template: params[:payload_template],
            variables: JSON.generate(params[:variables] || []),
            allowed_roles: params[:allowed_roles] ? JSON.generate(params[:allowed_roles]) : nil
          )

          webhook.save
          MCP::Tool::Response.new([{
            type: 'text',
            text: "Created webhook '#{webhook.name}'."
          }])
        rescue Sequel::ValidationFailed => e
          error("Validation error: #{e.message}")
        end

        def self.handle_list
          webhooks = SOT::Webhook.order(:name).all
          if webhooks.empty?
            return MCP::Tool::Response.new([{ type: 'text', text: 'No webhooks defined.' }])
          end

          lines = webhooks.map do |wh|
            vars = wh.parsed_variables
            roles = wh.parsed_allowed_roles
            parts = [
              "- #{wh.name}: #{wh.description}",
              "  URL: #{wh.http_method} #{wh.url}",
            ]
            parts << "  Headers: #{wh.parsed_headers.map { |k, v| "#{k}: #{v}" }.join(', ')}" unless wh.parsed_headers.empty?
            parts << "  Template: #{wh.payload_template}"
            if vars.any?
              parts << "  Variables:"
              vars.each { |v| parts << "    - #{v['name']}: #{v['description']}" }
            end
            parts << "  Allowed roles: #{roles.empty? ? 'admin only' : roles.join(', ')}"
            parts.join("\n")
          end

          MCP::Tool::Response.new([{ type: 'text', text: "Webhooks:\n#{lines.join("\n\n")}" }])
        end

        def self.handle_update(params)
          return error("'name' is required.") unless params[:name]

          webhook = SOT::Webhook.first(name: params[:name])
          return error("Webhook '#{params[:name]}' not found.") unless webhook

          updates = {}
          updates[:description] = params[:description] if params.key?(:description)
          updates[:url] = params[:url] if params.key?(:url)
          updates[:http_method] = params[:http_method] if params.key?(:http_method)
          updates[:headers] = JSON.generate(params[:headers]) if params.key?(:headers)
          updates[:payload_template] = params[:payload_template] if params.key?(:payload_template)
          updates[:variables] = JSON.generate(params[:variables]) if params.key?(:variables)
          updates[:allowed_roles] = JSON.generate(params[:allowed_roles]) if params.key?(:allowed_roles)

          webhook.update(updates) unless updates.empty?
          MCP::Tool::Response.new([{
            type: 'text',
            text: "Updated webhook '#{webhook.name}'."
          }])
        rescue Sequel::ValidationFailed => e
          error("Validation error: #{e.message}")
        end

        def self.handle_delete(params)
          return error("'name' is required.") unless params[:name]

          webhook = SOT::Webhook.first(name: params[:name])
          return error("Webhook '#{params[:name]}' not found.") unless webhook

          webhook.destroy
          MCP::Tool::Response.new([{
            type: 'text',
            text: "Deleted webhook '#{params[:name]}'."
          }])
        end

        def self.error(message)
          MCP::Tool::Response.new([{ type: 'text', text: message }], error: true)
        end
      end
    end
  end
end
