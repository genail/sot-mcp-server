module SOT
  module Tools
    module User
      class Whoami < MCP::Tool
        tool_name 'sot_whoami'

        description <<~DESC
          Returns the name of the currently authenticated user.
          Use this to identify yourself in the system.
        DESC

        input_schema(properties: {})

        def self.call(server_context:, **params)
          user = server_context[:user]
          role_name = user.role&.name || 'unknown'
          MCP::Tool::Response.new([{ type: 'text', text: "You are: #{user.name} (role: #{role_name})" }])
        end
      end
    end
  end
end
