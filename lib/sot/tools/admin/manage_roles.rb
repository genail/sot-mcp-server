module SOT
  module Tools
    module Admin
      class ManageRoles < MCP::Tool
        tool_name 'sot_admin_manage_roles'

        description <<~DESC
          Manage roles for the permission system.

          Actions:
          - create: Create a new role. Requires name. Optional: description.
          - list: List all roles.
          - update: Update a role's description. Requires name.
          - delete: Delete a role. Cannot delete system roles (admin, member) or roles still assigned to users.
        DESC

        input_schema(
          properties: {
            action: {
              type: 'string',
              enum: %w[create list update delete],
              description: 'The management action'
            },
            name: { type: 'string', description: 'Role name (lowercase alphanumeric with underscores)' },
            description: { type: 'string', description: 'Role description' }
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
            MCP::Tool::Response.new([{ type: 'text', text: "Unknown action '#{params[:action]}'." }], error: true)
          end
        end

        private

        def self.handle_create(params)
          return error("'name' is required.") unless params[:name]

          role = SOT::Role.new(
            name: params[:name],
            description: params[:description]
          )

          role.save
          MCP::Tool::Response.new([{
            type: 'text',
            text: "Created role '#{role.name}'."
          }])
        rescue Sequel::ValidationFailed => e
          error("Error: #{e.message}")
        end

        def self.handle_list
          roles = SOT::Role.order(:name).all
          if roles.empty?
            return MCP::Tool::Response.new([{ type: 'text', text: 'No roles found.' }])
          end

          lines = roles.map do |r|
            user_count = SOT::User.where(role_id: r.id).count
            system = r.system_role? ? ' (system)' : ''
            desc = r.description ? " — #{r.description}" : ''
            "- #{r.name}#{system}#{desc} (#{user_count} user#{'s' unless user_count == 1})"
          end
          MCP::Tool::Response.new([{ type: 'text', text: "Roles:\n#{lines.join("\n")}" }])
        end

        def self.handle_update(params)
          return error("'name' is required.") unless params[:name]

          role = SOT::Role.first(name: params[:name])
          return error("Role '#{params[:name]}' not found.") unless role

          updates = {}
          updates[:description] = params[:description] if params.key?(:description)

          role.update(updates) unless updates.empty?
          MCP::Tool::Response.new([{
            type: 'text',
            text: "Updated role '#{role.name}'."
          }])
        rescue Sequel::ValidationFailed => e
          error("Error: #{e.message}")
        end

        def self.handle_delete(params)
          return error("'name' is required.") unless params[:name]

          role = SOT::Role.first(name: params[:name])
          return error("Role '#{params[:name]}' not found.") unless role

          if role.system_role?
            return error("Cannot delete system role '#{role.name}'. System roles (admin, member) cannot be removed.")
          end

          user_count = SOT::User.where(role_id: role.id).count
          if user_count > 0
            return error("Cannot delete role '#{role.name}': #{user_count} user#{'s' unless user_count == 1} still assigned. Reassign them first.")
          end

          schemas_using_role = SOT::Schema.all.select do |s|
            [s.parsed_read_roles, s.parsed_create_roles, s.parsed_update_roles, s.parsed_delete_roles]
              .any? { |roles| roles.include?(role.name) }
          end
          if schemas_using_role.any?
            names = schemas_using_role.map(&:full_name).join(', ')
            return error("Cannot delete role '#{role.name}': still referenced in schema ACLs for: #{names}. Remove the role from those schemas first.")
          end

          role.destroy
          MCP::Tool::Response.new([{
            type: 'text',
            text: "Deleted role '#{params[:name]}'."
          }])
        end

        def self.error(message)
          MCP::Tool::Response.new([{ type: 'text', text: message }], error: true)
        end
      end
    end
  end
end
