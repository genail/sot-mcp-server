module SOT
  module Middleware
    # Rack 3.x requires lowercase response header names.
    # Sinatra and the MCP gem emit mixed-case headers (e.g. "Content-Type").
    # This middleware normalises them so Rack::Lint is satisfied.
    class DowncaseHeaders
      def initialize(app)
        @app = app
      end

      def call(env)
        status, headers, body = @app.call(env)
        downcased = headers.each_with_object({}) { |(k, v), h| h[k.downcase] = v }
        [status, downcased, body]
      end
    end
  end
end
