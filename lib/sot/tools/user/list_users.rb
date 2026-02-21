module SOT
  module Tools
    module User
      class ListUsers < MCP::Tool
        tool_name 'sot_list_users'

        description <<~DESC
          List all user names in the system.
          Use this to discover valid usernames when you need to reference a user (e.g., assigning a task).
        DESC

        input_schema(properties: {})

        def self.call(server_context:, **params)
          users = SOT::UserService.list

          if users.empty?
            return MCP::Tool::Response.new([{ type: 'text', text: 'No users found.' }])
          end

          lines = users.map { |u| "- #{u.name}" }
          MCP::Tool::Response.new([{ type: 'text', text: "Users:\n#{lines.join("\n")}" }])
        end
      end
    end
  end
end
