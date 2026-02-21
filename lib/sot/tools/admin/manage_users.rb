module SOT
  module Tools
    module Admin
      class ManageUsers < MCP::Tool
        tool_name 'sot_admin_manage_users'

        description <<~DESC
          Manage users and their authentication tokens.

          Actions:
          - create: Create a new user. Returns the token (shown once, save it).
          - list: List all users.
          - delete: Delete a user by name.
          - regenerate_token: Generate a new token for a user. Returns the new token.
        DESC

        input_schema(
          properties: {
            action: {
              type: 'string',
              enum: %w[create list delete regenerate_token],
              description: 'The management action'
            },
            name: { type: 'string', description: 'User name (required for create/delete/regenerate_token)' },
            is_admin: { type: 'boolean', description: 'Whether the user is an admin (for create, default false)' }
          },
          required: ['action']
        )

        def self.call(server_context:, **params)
          case params[:action]
          when 'create' then handle_create(params)
          when 'list' then handle_list
          when 'delete' then handle_delete(params)
          when 'regenerate_token' then handle_regenerate(params)
          else
            MCP::Tool::Response.new([{ type: 'text', text: "Unknown action '#{params[:action]}'." }], error: true)
          end
        end

        private

        def self.handle_create(params)
          return MCP::Tool::Response.new([{ type: 'text', text: "'name' is required." }], error: true) unless params[:name]

          user, token = SOT::UserService.create(
            name: params[:name],
            is_admin: params[:is_admin] || false
          )

          MCP::Tool::Response.new([{
            type: 'text',
            text: "Created user '#{user.name}' (admin: #{user.is_admin}).\nToken (save this, it won't be shown again): #{token}"
          }])
        rescue Sequel::ValidationFailed => e
          MCP::Tool::Response.new([{ type: 'text', text: "Error: #{e.message}" }], error: true)
        end

        def self.handle_list
          users = SOT::UserService.list
          if users.empty?
            return MCP::Tool::Response.new([{ type: 'text', text: 'No users found.' }])
          end

          lines = users.map { |u| "- #{u.name} (admin: #{u.is_admin})" }
          MCP::Tool::Response.new([{ type: 'text', text: "Users:\n#{lines.join("\n")}" }])
        end

        def self.handle_delete(params)
          return MCP::Tool::Response.new([{ type: 'text', text: "'name' is required." }], error: true) unless params[:name]

          user = SOT::UserService.find_by_name(params[:name])
          return MCP::Tool::Response.new([{ type: 'text', text: "User '#{params[:name]}' not found." }], error: true) unless user

          SOT::UserService.delete(user)
          MCP::Tool::Response.new([{ type: 'text', text: "Deleted user '#{params[:name]}'." }])
        rescue Sequel::ForeignKeyConstraintViolation
          MCP::Tool::Response.new([{
            type: 'text',
            text: "Cannot delete user '#{params[:name]}': they have associated records or activity log entries. Reassign or delete those first."
          }], error: true)
        end

        def self.handle_regenerate(params)
          return MCP::Tool::Response.new([{ type: 'text', text: "'name' is required." }], error: true) unless params[:name]

          user = SOT::UserService.find_by_name(params[:name])
          return MCP::Tool::Response.new([{ type: 'text', text: "User '#{params[:name]}' not found." }], error: true) unless user

          user, token = SOT::UserService.regenerate_token(user)
          MCP::Tool::Response.new([{
            type: 'text',
            text: "Regenerated token for '#{user.name}'.\nNew token (save this, it won't be shown again): #{token}"
          }])
        end
      end
    end
  end
end
