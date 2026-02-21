module SOT
  module Middleware
    class TokenAuth
      def initialize(app)
        @app = app
      end

      def call(env)
        token = extract_token(env)

        unless token
          return [401, { 'content-type' => 'application/json' }, [
            '{"error":"Authentication required. Provide a Bearer token in the Authorization header."}'
          ]]
        end

        user = SOT::User.authenticate(token)

        unless user
          return [401, { 'content-type' => 'application/json' }, [
            '{"error":"Invalid token. Check your SOT_TOKEN value."}'
          ]]
        end

        env['sot.current_user'] = user
        @app.call(env)
      end

      private

      def extract_token(env)
        auth = env['HTTP_AUTHORIZATION']
        return nil unless auth

        scheme, token = auth.split(' ', 2)
        return nil unless scheme&.downcase == 'bearer' && token && !token.empty?

        token
      end
    end
  end
end
