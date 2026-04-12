module SOT
  module Middleware
    class AdminGate
      def initialize(app)
        @app = app
      end

      def call(env)
        user = env['sot.current_user']

        unless user&.admin?
          return [403, { 'content-type' => 'application/json' }, [
            '{"error":"Admin access required. This endpoint is restricted to administrators."}'
          ]]
        end

        @app.call(env)
      end
    end
  end
end
