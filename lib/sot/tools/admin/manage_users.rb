module SOT
  module Tools
    module Admin
      class ManageUsers < MCP::Tool
        tool_name 'sot_admin_manage_users'

        description <<~DESC
          Manage users and their authentication tokens.

          Actions:
          - create: Create a new user. Returns the token (shown once, save it).
          - list: List all users (shows active/inactive status).
          - deactivate: Deactivate a user by name. They will no longer be able to authenticate.
          - activate: Reactivate a previously deactivated user.
          - regenerate_token: Generate a new token for a user. Returns the new token.
          - rename: Rename a user. Automatically updates all user-type fields referencing the old name across all records.
        DESC

        input_schema(
          properties: {
            action: {
              type: 'string',
              enum: %w[create list deactivate activate regenerate_token rename],
              description: 'The management action'
            },
            name: { type: 'string', description: 'User name (required for create/deactivate/activate/regenerate_token/rename)' },
            new_name: { type: 'string', description: 'New name for the user (required for rename)' },
            is_admin: { type: 'boolean', description: 'Whether the user is an admin (for create, default false)' }
          },
          required: ['action']
        )

        def self.call(server_context:, **params)
          case params[:action]
          when 'create' then handle_create(params)
          when 'list' then handle_list
          when 'deactivate' then handle_deactivate(params)
          when 'activate' then handle_activate(params)
          when 'regenerate_token' then handle_regenerate(params)
          when 'rename' then handle_rename(params, server_context)
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

          lines = users.map do |u|
            status = u.is_active ? 'active' : 'inactive'
            "- #{u.name} (admin: #{u.is_admin}, status: #{status})"
          end
          MCP::Tool::Response.new([{ type: 'text', text: "Users:\n#{lines.join("\n")}" }])
        end

        def self.handle_deactivate(params)
          return MCP::Tool::Response.new([{ type: 'text', text: "'name' is required." }], error: true) unless params[:name]

          user = SOT::UserService.find_by_name(params[:name])
          return MCP::Tool::Response.new([{ type: 'text', text: "User '#{params[:name]}' not found." }], error: true) unless user

          unless user.is_active
            return MCP::Tool::Response.new([{ type: 'text', text: "User '#{params[:name]}' is already inactive." }], error: true)
          end

          SOT::UserService.deactivate(user)
          MCP::Tool::Response.new([{ type: 'text', text: "Deactivated user '#{params[:name]}'. They can no longer authenticate." }])
        end

        def self.handle_activate(params)
          return MCP::Tool::Response.new([{ type: 'text', text: "'name' is required." }], error: true) unless params[:name]

          user = SOT::UserService.find_by_name(params[:name])
          return MCP::Tool::Response.new([{ type: 'text', text: "User '#{params[:name]}' not found." }], error: true) unless user

          if user.is_active
            return MCP::Tool::Response.new([{ type: 'text', text: "User '#{params[:name]}' is already active." }], error: true)
          end

          SOT::UserService.activate(user)
          MCP::Tool::Response.new([{ type: 'text', text: "Reactivated user '#{params[:name]}'. They can authenticate again." }])
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

        def self.handle_rename(params, server_context)
          return MCP::Tool::Response.new([{ type: 'text', text: "'name' is required." }], error: true) unless params[:name]
          return MCP::Tool::Response.new([{ type: 'text', text: "'new_name' is required." }], error: true) unless params[:new_name]

          user = SOT::UserService.find_by_name(params[:name])
          return MCP::Tool::Response.new([{ type: 'text', text: "User '#{params[:name]}' not found." }], error: true) unless user

          admin_user = server_context && server_context[:user]

          SOT::UserService.rename(user, new_name: params[:new_name], admin_user: admin_user)
          MCP::Tool::Response.new([{
            type: 'text',
            text: "Renamed user '#{params[:name]}' to '#{params[:new_name]}'. All user-type field references have been updated."
          }])
        rescue ArgumentError => e
          MCP::Tool::Response.new([{ type: 'text', text: "Error: #{e.message}" }], error: true)
        rescue Sequel::ValidationFailed => e
          MCP::Tool::Response.new([{ type: 'text', text: "Error: #{e.message}" }], error: true)
        end
      end
    end
  end
end
