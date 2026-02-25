module SOT
  module Tools
    module Admin
      class ManageSchema < MCP::Tool
        tool_name 'sot_admin_manage_schema'

        description <<~DESC
          Create, update, or delete table definitions.

          Actions:
          - create: Define a new table. Requires namespace, name, fields. Optional: description, states.
          - update: Modify an existing table. Requires table. Provide fields to change.
          - delete: Remove a table and all its records. Requires table.

          Fields format: Array of { "name": "...", "type": "string|integer|float|boolean|text|date|datetime|user", "description": "...", "required": true/false }
          States format: Array of { "name": "...", "description": "..." } (omit for stateless tables)

          IMPORTANT: Always provide clear descriptions for the table, each field, and each state.
          These descriptions guide agents in understanding how to use the table correctly.
        DESC

        input_schema(
          properties: {
            action: {
              type: 'string',
              enum: %w[create update delete],
              description: 'The management action'
            },
            table: {
              type: 'string',
              description: 'Table name for update/delete (e.g., "org.locks")'
            },
            namespace: { type: 'string', description: 'Namespace for create (e.g., "org", "project")' },
            name: { type: 'string', description: 'Table name for create (e.g., "locks", "deployments")' },
            description: { type: 'string', description: 'Description of the table purpose' },
            fields: {
              type: 'array',
              description: 'Field definitions',
              items: {
                type: 'object',
                properties: {
                  name: { type: 'string' },
                  type: { type: 'string', enum: %w[string integer float boolean text datetime user] },
                  description: { type: 'string' },
                  required: { type: 'boolean' }
                }
              }
            },
            states: {
              type: 'array',
              description: 'State definitions (omit for stateless tables)',
              items: {
                type: 'object',
                properties: {
                  name: { type: 'string' },
                  description: { type: 'string' }
                }
              }
            }
          },
          required: ['action']
        )

        def self.call(server_context:, **params)
          case params[:action]
          when 'create' then handle_create(params)
          when 'update' then handle_update(params)
          when 'delete' then handle_delete(params)
          else
            MCP::Tool::Response.new([{ type: 'text', text: "Unknown action '#{params[:action]}'." }], error: true)
          end
        end

        private

        def self.handle_create(params)
          schema = SOT::SchemaService.create(
            namespace: params[:namespace],
            name: params[:name],
            description: params[:description],
            fields: params[:fields],
            states: params[:states]
          )

          MCP::Tool::Response.new([{
            type: 'text',
            text: "Created table '#{schema.full_name}'."
          }])
        rescue ArgumentError, Sequel::ValidationFailed => e
          MCP::Tool::Response.new([{ type: 'text', text: "Error: #{e.message}" }], error: true)
        end

        def self.handle_update(params)
          schema = SOT::SchemaService.resolve(params[:table])
          return MCP::Tool::Response.new([{ type: 'text', text: "Table '#{params[:table]}' not found." }], error: true) unless schema

          attrs = {}
          attrs[:description] = params[:description] if params.key?(:description)
          attrs[:fields] = params[:fields] if params.key?(:fields)
          attrs[:states] = params[:states] if params.key?(:states)
          attrs[:namespace] = params[:namespace] if params.key?(:namespace)
          attrs[:name] = params[:name] if params.key?(:name)

          SOT::SchemaService.update(schema, **attrs)
          MCP::Tool::Response.new([{
            type: 'text',
            text: "Updated table '#{schema.full_name}'."
          }])
        rescue ArgumentError, Sequel::ValidationFailed => e
          MCP::Tool::Response.new([{ type: 'text', text: "Error: #{e.message}" }], error: true)
        end

        def self.handle_delete(params)
          schema = SOT::SchemaService.resolve(params[:table])
          return MCP::Tool::Response.new([{ type: 'text', text: "Table '#{params[:table]}' not found." }], error: true) unless schema

          name = schema.full_name
          SOT::SchemaService.delete(schema)
          MCP::Tool::Response.new([{
            type: 'text',
            text: "Deleted table '#{name}' and all its records."
          }])
        rescue Sequel::ForeignKeyConstraintViolation
          MCP::Tool::Response.new([{
            type: 'text',
            text: "Cannot delete table '#{schema.full_name}': it has associated activity log entries. Delete those first."
          }], error: true)
        end
      end
    end
  end
end
