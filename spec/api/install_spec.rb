require 'spec_helper'

RSpec.describe 'POST /install', type: :api do
  def app
    Rack::Builder.new do
      map '/install' do
        run SOT::InstallApp
      end

      map '/api' do
        use SOT::Middleware::TokenAuth
        run SOT::ApiApp
      end
    end
  end

  context 'when no users exist' do
    it 'creates an admin user and returns the token' do
      post '/install'

      expect(last_response.status).to eq(201)
      expect(json_body['token']).to be_a(String)
      expect(json_body['token'].length).to eq(64)
      expect(json_body['message']).to include('will not be shown again')
    end

    it 'creates exactly one admin user' do
      post '/install'

      expect(SOT::User.count).to eq(1)
      user = SOT::User.first
      expect(user.name).to eq('admin')
      expect(user.is_admin).to be true
    end
  end

  context 'when users already exist' do
    before { create(:user) }

    it 'returns 403' do
      post '/install'

      expect(last_response.status).to eq(403)
      expect(json_body['error']).to include('already installed')
    end
  end

  context 'returned token authenticates successfully' do
    it 'can be used to call the API' do
      post '/install'
      token = json_body['token']

      get '/api/schemas', {}, { 'HTTP_AUTHORIZATION' => "Bearer #{token}" }

      expect(last_response.status).to eq(200)
    end
  end
end
