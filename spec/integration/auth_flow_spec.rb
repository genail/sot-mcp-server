require 'spec_helper'

RSpec.describe 'Auth flow', type: :api do
  let(:admin_pair) { SOT::User.create_with_token(name: 'admin', is_admin: true) }
  let(:admin_token) { admin_pair.last }

  let(:user_pair) { SOT::User.create_with_token(name: 'dev') }
  let(:user_token) { user_pair.last }

  describe 'unauthenticated access' do
    it 'returns 401 for API without token' do
      get '/api/schemas'
      expect(last_response.status).to eq(401)
    end

    it 'returns 401 for invalid token' do
      get '/api/schemas', {}, auth_header('bad_token')
      expect(last_response.status).to eq(401)
    end
  end

  describe 'admin gating' do
    it 'allows admin to access admin endpoints' do
      post_json '/api/admin/schemas', {
        namespace: 'test', name: 'items',
        fields: [{ 'name' => 'title', 'type' => 'string' }]
      }, auth_header(admin_token)

      expect(last_response.status).to eq(201)
    end

    it 'rejects non-admin from admin endpoints' do
      post_json '/api/admin/schemas', {
        namespace: 'test', name: 'items',
        fields: [{ 'name' => 'title', 'type' => 'string' }]
      }, auth_header(user_token)

      expect(last_response.status).to eq(403)
    end
  end

  describe 'regular user access' do
    before do
      create(:table_schema, namespace: 'org', name: 'docs')
    end

    it 'allows authenticated user to read schemas' do
      get '/api/schemas', {}, auth_header(user_token)
      expect(last_response.status).to eq(200)
      expect(json_body['schemas']).not_to be_empty
    end

    it 'allows authenticated user to create records' do
      post_json '/api/records', {
        table: 'org.docs',
        data: { 'title' => 'My Doc' }
      }, auth_header(user_token)

      expect(last_response.status).to eq(201)
    end
  end
end
