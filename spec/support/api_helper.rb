module ApiHelper
  include Rack::Test::Methods

  def app
    # Match production config.ru: /api mapped to ApiApp with TokenAuth
    Rack::Builder.new do
      map '/api' do
        use SOT::Middleware::TokenAuth
        run SOT::ApiApp
      end
    end
  end

  def auth_header(token)
    { 'HTTP_AUTHORIZATION' => "Bearer #{token}" }
  end

  def json_body
    JSON.parse(last_response.body)
  end

  def post_json(path, body, headers = {})
    post path, body.to_json, headers.merge('CONTENT_TYPE' => 'application/json')
  end

  def patch_json(path, body, headers = {})
    patch path, body.to_json, headers.merge('CONTENT_TYPE' => 'application/json')
  end

  def delete_json(path, body = {}, headers = {})
    delete path, body.to_json, headers.merge('CONTENT_TYPE' => 'application/json')
  end
end

RSpec.configure do |config|
  config.include ApiHelper, type: :api
end
