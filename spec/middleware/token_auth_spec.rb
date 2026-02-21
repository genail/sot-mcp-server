require 'spec_helper'

RSpec.describe SOT::Middleware::TokenAuth do
  let(:inner_app) do
    ->(env) { [200, { 'content-type' => 'text/plain' }, ["user:#{env['sot.current_user']&.name}"]] }
  end
  let(:app) { described_class.new(inner_app) }

  let(:user) { create(:user) }
  let(:token) { user.instance_variable_get(:@raw_token) || create_user_with_token.last }

  def create_user_with_token
    SOT::User.create_with_token(name: "auth_test_#{SecureRandom.hex(4)}")
  end

  def make_request(auth_header: nil)
    env = Rack::MockRequest.env_for('/', 'HTTP_AUTHORIZATION' => auth_header)
    app.call(env)
  end

  describe 'with valid token' do
    it 'authenticates and passes user to inner app' do
      user, token = create_user_with_token
      status, _headers, body = make_request(auth_header: "Bearer #{token}")

      expect(status).to eq(200)
      expect(body.first).to eq("user:#{user.name}")
    end
  end

  describe 'with missing Authorization header' do
    it 'returns 401' do
      status, headers, body = make_request

      expect(status).to eq(401)
      expect(headers['content-type']).to eq('application/json')
      expect(body.first).to include('Authentication required')
    end
  end

  describe 'with empty Authorization header' do
    it 'returns 401' do
      status, _headers, body = make_request(auth_header: '')

      expect(status).to eq(401)
      expect(body.first).to include('Authentication required')
    end
  end

  describe 'with non-Bearer scheme' do
    it 'returns 401' do
      status, _headers, body = make_request(auth_header: 'Basic abc123')

      expect(status).to eq(401)
      expect(body.first).to include('Authentication required')
    end
  end

  describe 'with Bearer but no token' do
    it 'returns 401' do
      status, _headers, body = make_request(auth_header: 'Bearer ')

      expect(status).to eq(401)
      expect(body.first).to include('Authentication required')
    end
  end

  describe 'with invalid token' do
    it 'returns 401 with helpful message' do
      status, _headers, body = make_request(auth_header: 'Bearer wrong_token')

      expect(status).to eq(401)
      expect(body.first).to include('Invalid token')
    end
  end

  describe 'with case-insensitive Bearer' do
    it 'accepts lowercase bearer' do
      user, token = create_user_with_token
      status, _headers, body = make_request(auth_header: "bearer #{token}")

      expect(status).to eq(200)
      expect(body.first).to include(user.name)
    end
  end
end
