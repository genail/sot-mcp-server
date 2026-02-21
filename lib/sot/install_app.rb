require 'sinatra/base'
require 'sinatra/json'

module SOT
  class InstallApp < Sinatra::Base
    helpers Sinatra::JSON

    before do
      content_type :json
    end

    post '/' do
      if SOT::User.count > 0
        halt 403, json(error: 'System already installed.')
      end

      user, token = SOT::User.create_with_token(name: 'admin', is_admin: true)

      [201, json(
        message: 'Admin user created. Save this token — it will not be shown again.',
        token: token
      )]
    end
  end
end
