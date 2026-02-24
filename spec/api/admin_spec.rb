require 'spec_helper'

RSpec.describe 'Admin API', type: :api do
  let(:admin_pair) { SOT::User.create_with_token(name: 'admin_api', is_admin: true) }
  let(:admin) { admin_pair.first }
  let(:admin_token) { admin_pair.last }

  let(:user_pair) { SOT::User.create_with_token(name: 'regular_user') }
  let(:user_token) { user_pair.last }

  describe 'POST /api/admin/schemas' do
    it 'creates a schema' do
      post_json '/api/admin/schemas', {
        namespace: 'org',
        name: 'locks',
        description: 'Resource locks',
        fields: [{ 'name' => 'title', 'type' => 'string', 'required' => true }],
        states: [{ 'name' => 'open' }, { 'name' => 'closed' }]
      }, auth_header(admin_token)

      expect(last_response.status).to eq(201)
      expect(json_body['schema']['full_name']).to eq('org.locks')
      expect(json_body['schema']['stateful']).to be true
    end

    it 'returns 422 on validation error' do
      post_json '/api/admin/schemas', {
        namespace: 'org',
        name: 'bad',
        fields: []
      }, auth_header(admin_token)

      expect(last_response.status).to eq(422)
      expect(json_body['error']).to include('cannot be empty')
    end

    it 'rejects non-admin users' do
      post_json '/api/admin/schemas', {
        namespace: 'org',
        name: 'locks',
        fields: [{ 'name' => 'title', 'type' => 'string' }]
      }, auth_header(user_token)

      expect(last_response.status).to eq(403)
    end
  end

  describe 'PATCH /api/admin/schemas/:id' do
    let!(:schema) { create(:table_schema, namespace: 'org', name: 'docs') }

    it 'updates a schema' do
      patch_json "/api/admin/schemas/#{schema.id}", {
        description: 'Updated description'
      }, auth_header(admin_token)

      expect(last_response.status).to eq(200)
      expect(json_body['schema']['description']).to eq('Updated description')
    end

    it 'returns 404 for unknown schema' do
      patch_json '/api/admin/schemas/99999', {
        description: 'x'
      }, auth_header(admin_token)

      expect(last_response.status).to eq(404)
    end
  end

  describe 'DELETE /api/admin/schemas/:id' do
    let!(:schema) { create(:table_schema, namespace: 'org', name: 'temp') }

    it 'deletes a schema' do
      delete "/api/admin/schemas/#{schema.id}", {}, auth_header(admin_token)

      expect(last_response.status).to eq(200)
      expect(json_body['message']).to include('Deleted')
      expect(SOT::Schema[schema.id]).to be_nil
    end

    it 'returns 404 for unknown schema' do
      delete '/api/admin/schemas/99999', {}, auth_header(admin_token)

      expect(last_response.status).to eq(404)
    end

    it 'rejects non-admin users' do
      delete "/api/admin/schemas/#{schema.id}", {}, auth_header(user_token)

      expect(last_response.status).to eq(403)
    end
  end
end
