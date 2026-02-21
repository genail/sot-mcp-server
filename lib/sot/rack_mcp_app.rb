require 'mcp'
require 'mcp/server/transports/streamable_http_transport'
require 'rack'

module SOT
  class RackMcpApp
    def initialize(tools:)
      @tools = tools
    end

    def call(env)
      user = env['sot.current_user']
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
