require 'mcp'
require 'mcp/server/transports/streamable_http_transport'
require 'rack'
require_relative 'middleware/mcp_type_coercer'

module SOT
  class RackMcpApp
    def initialize(tools:)
      @tools = tools
      @tools_by_name = tools.each_with_object({}) do |t, h|
        name = t.respond_to?(:tool_name) ? t.tool_name : t.name_value
        h[name] = t if name
      end
    end

    def call(env)
      user = env['sot.current_user']
      SOT::Middleware::McpTypeCoercer.preprocess!(env, @tools_by_name)
      request = Rack::Request.new(env)

      server = MCP::Server.new(
        name: 'sot-server',
        version: '0.1.0',
        tools: @tools,
        server_context: { user: user }
      )

      transport = MCP::Server::Transports::StreamableHTTPTransport.new(server, stateless: true)
      transport.handle_request(request)
    end
  end
end
