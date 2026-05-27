module SOT
  module Tools
    module Admin
      class ManageSchema < MCP::Tool
        tool_name 'sot_admin_manage_schema'

        description <<~DESC
          Create, update, delete, or reorder table definitions.

          Actions:
          - create: Define a new table. Requires namespace, name, fields. Optional: description, states.
          - update: Modify an existing table. Requires table. Fields use MERGE semantics:
            * New fields (by name) are appended to the table.
            * Existing fields (by name) have their properties updated.
            * If the update would remove fields, you must pass confirm_delete_fields with those names.
          - delete: Remove a table and all its records. Requires table.
          - reorder_fields: Change field display order. Requires table and field_order (all field names in desired order).

          Fields format: Array of { "name": "...", "type": "string|integer|float|boolean|text|date|datetime|user", "description": "...", "required": true/false }
          States format: Array of { "name": "...", "description": "..." } (omit for stateless tables)

          IMPORTANT: Always provide clear descriptions for the table, each field, and each state.
          These descriptions guide agents in understanding how to use the table correctly.
        DESC

        input_schema(
          properties: {
            action: {
              type: 'string',
              enum: %w[create update delete reorder_fields],
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
                  type: { type: 'string', enum: %w[string integer float boolean text date datetime user] },
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
            },
            read_roles: {
              type: 'array',
              items: { type: 'string' },
              description: 'Role names that can read records (empty = admin only)'
            },
            create_roles: {
              type: 'array',
              items: { type: 'string' },
              description: 'Role names that can create records (empty = admin only)'
            },
            update_roles: {
              type: 'array',
              items: { type: 'string' },
              description: 'Role names that can update records (empty = admin only)'
            },
            delete_roles: {
              type: 'array',
              items: { type: 'string' },
              description: 'Role names that can delete records (empty = admin only)'
            },
            confirm_delete_fields: {
              type: 'array',
              items: { type: 'string' },
              description: 'Field names to confirm deletion (required when update would remove fields)'
            },
            field_order: {
              type: 'array',
              items: { type: 'string' },
              description: 'Ordered list of all field names (for reorder_fields action)'
            }
          },
          required: ['action']
        )

        def self.call(server_context:, **params)
          case params[:action]
          when 'create' then handle_create(params)
          when 'update' then handle_update(params)
          when 'delete' then handle_delete(params)
          when 'reorder_fields' then handle_reorder_fields(params)
          else
            MCP::Tool::Response.new([{ type: 'text', text: "Unknown action '#{params[:action]}'." }], error: true)
          end
        end

        private

        def self.handle_create(params)
          acl = extract_acl(params)
          schema = SOT::SchemaService.create(
            namespace: params[:namespace],
            name: params[:name],
            description: params[:description],
            fields: params[:fields],
            states: params[:states],
            **acl
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
          attrs[:read_roles] = params[:read_roles] if params.key?(:read_roles)
          attrs[:create_roles] = params[:create_roles] if params.key?(:create_roles)
          attrs[:update_roles] = params[:update_roles] if params.key?(:update_roles)
          attrs[:delete_roles] = params[:delete_roles] if params.key?(:delete_roles)

          confirm = params.key?(:confirm_delete_fields) ? params[:confirm_delete_fields] : []
          result = SOT::SchemaService.update(schema, confirm_delete_fields: confirm, **attrs)

          text = format_update_response(schema, result[:field_changes])
          MCP::Tool::Response.new([{ type: 'text', text: text }])
        rescue ArgumentError, Sequel::ValidationFailed => e
          MCP::Tool::Response.new([{ type: 'text', text: "Error: #{e.message}" }], error: true)
        end

        def self.handle_reorder_fields(params)
          schema = SOT::SchemaService.resolve(params[:table])
          return MCP::Tool::Response.new([{ type: 'text', text: "Table '#{params[:table]}' not found." }], error: true) unless schema

          result = SOT::SchemaService.reorder_fields(schema, params[:field_order])

          if result[:changed]
            text = "Reordered fields for '#{schema.full_name}': #{result[:new_order].join(', ')} (was: #{result[:old_order].join(', ')})."
          else
            text = "No changes — field order is already: #{schema.parsed_fields.map { |f| f['name'] }.join(', ')}."
          end

          MCP::Tool::Response.new([{ type: 'text', text: text }])
        rescue ArgumentError => e
          MCP::Tool::Response.new([{ type: 'text', text: "Error: #{e.message}" }], error: true)
        end

        def self.format_update_response(schema, field_changes)
          parts = ["Updated table '#{schema.full_name}'."]

          return parts.join("\n") unless field_changes

          if field_changes[:added].any?
            field_changes[:added].each do |f|
              req = f['required'] ? ', required' : ''
              desc = f['description'] ? " — #{f['description']}" : ''
              parts << "  Added field '#{f['name']}' (#{f['type']}#{req})#{desc}."
            end
          end

          if field_changes[:updated].any?
            field_changes[:updated].each do |change|
              change_details = change[:changes].map { |k, (old_v, new_v)| "#{k}: #{old_v.inspect} → #{new_v.inspect}" }
              parts << "  Updated field '#{change[:name]}': #{change_details.join(', ')}."
            end
          end

          if field_changes[:removed].any?
            field_changes[:removed].each do |f|
              req = f['required'] ? ', required' : ''
              desc = f['description'] ? ", description: #{f['description'].inspect}" : ''
              parts << "  Removed field '#{f['name']}' (#{f['type']}#{req}#{desc}). Record data is preserved. To restore: add field {\"name\": \"#{f['name']}\", \"type\": \"#{f['type']}\"}."
            end
          end

          if field_changes[:added].empty? && field_changes[:updated].empty? && field_changes[:removed].empty?
            parts << "  No field changes."
          end

          parts.join("\n")
        end

        def self.extract_acl(params)
          acl = {}
          %i[read_roles create_roles update_roles delete_roles].each do |key|
            acl[key] = params[key] if params.key?(key)
          end
          acl
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
