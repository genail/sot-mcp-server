require 'spec_helper'

RSpec.describe 'Records API', type: :api do
  let(:user_pair) { SOT::User.create_with_token(name: 'api_user') }
  let(:user) { user_pair.first }
  let(:token) { user_pair.last }
  let!(:schema) { create(:table_schema, :stateful, namespace: 'org', name: 'locks') }

  describe 'GET /api/records/:table' do
    before do
      SOT::MutationService.create(schema: schema, data: { 'title' => 'Lock A' }, state: 'open', user: user)
      SOT::MutationService.create(schema: schema, data: { 'title' => 'Lock B' }, state: 'closed', user: user)
    end

    it 'lists records for table' do
      get '/api/records/org.locks', {}, auth_header(token)

      expect(last_response.status).to eq(200)
      expect(json_body['records'].length).to eq(2)
      expect(json_body['total']).to eq(2)
    end

    it 'filters by state' do
      get '/api/records/org.locks', { state: 'open' }, auth_header(token)

      expect(last_response.status).to eq(200)
      expect(json_body['records'].length).to eq(1)
      expect(json_body['records'].first['state']).to eq('open')
    end

    it 'filters by JSON fields' do
      get '/api/records/org.locks', { filters: '{"title":"Lock A"}' }, auth_header(token)

      expect(last_response.status).to eq(200)
      expect(json_body['records'].length).to eq(1)
    end

    it 'returns 404 for unknown table' do
      get '/api/records/nonexistent', {}, auth_header(token)

      expect(last_response.status).to eq(404)
      expect(json_body['error']).to include('not found')
    end

    it 'supports pagination' do
      get '/api/records/org.locks', { limit: '1', offset: '0' }, auth_header(token)

      expect(last_response.status).to eq(200)
      expect(json_body['records'].length).to eq(1)
      expect(json_body['total']).to eq(2)
    end

    it 'returns 400 for unknown filter fields' do
      get '/api/records/org.locks', { filters: '{"nonexistent":"value"}' }, auth_header(token)

      expect(last_response.status).to eq(400)
      expect(json_body['error']).to include('Unknown filter fields')
    end

    it 'returns 400 for non-object JSON filters' do
      get '/api/records/org.locks', { filters: '["not","an","object"]' }, auth_header(token)

      expect(last_response.status).to eq(400)
      expect(json_body['error']).to include('Filters must be a JSON object')
    end
  end

  describe 'POST /api/records' do
    it 'creates a record' do
      post_json '/api/records', {
        table: 'org.locks',
        data: { 'title' => 'New Lock' },
        state: 'open'
      }, auth_header(token)

      expect(last_response.status).to eq(201)
      expect(json_body['record']['data']['title']).to eq('New Lock')
      expect(json_body['record']['state']).to eq('open')
    end

    it 'returns 404 for unknown table' do
      post_json '/api/records', {
        table: 'nonexistent',
        data: { 'title' => 'x' }
      }, auth_header(token)

      expect(last_response.status).to eq(404)
    end

    it 'returns 422 on validation error' do
      post_json '/api/records', {
        table: 'org.locks',
        data: { 'title' => 'x', 'bad_field' => 'y' }
      }, auth_header(token)

      expect(last_response.status).to eq(422)
      expect(json_body['error']).to include('Unknown fields')
    end

    it 'returns 400 without table' do
      post_json '/api/records', { data: { 'title' => 'x' } }, auth_header(token)

      expect(last_response.status).to eq(400)
      expect(json_body['error']).to include("'table' is required")
    end
  end

  describe 'PATCH /api/records/:id' do
    let!(:record) do
      SOT::MutationService.create(schema: schema, data: { 'title' => 'Original' }, state: 'open', user: user)
    end

    it 'updates a record' do
      patch_json "/api/records/#{record.id}", {
        data: { 'title' => 'Updated' },
        version: 1
      }, auth_header(token)

      expect(last_response.status).to eq(200)
      expect(json_body['record']['data']['title']).to eq('Updated')
      expect(json_body['record']['version']).to eq(2)
    end

    it 'updates state with preconditions' do
      patch_json "/api/records/#{record.id}", {
        state: 'closed',
        preconditions: { 'state' => 'open' },
        version: 1
      }, auth_header(token)

      expect(last_response.status).to eq(200)
      expect(json_body['record']['state']).to eq('closed')
    end

    it 'returns 409 on version conflict' do
      patch_json "/api/records/#{record.id}", {
        data: { 'title' => 'New' },
        version: 99
      }, auth_header(token)

      expect(last_response.status).to eq(409)
      expect(json_body['error']).to include('Version conflict')
    end

    it 'returns 409 on precondition failure' do
      patch_json "/api/records/#{record.id}", {
        state: 'closed',
        preconditions: { 'state' => 'closed' },
        version: 1
      }, auth_header(token)

      expect(last_response.status).to eq(409)
      expect(json_body['error']).to include('Precondition failed')
    end

    it 'returns 404 for nonexistent record' do
      patch_json '/api/records/99999', { data: { 'title' => 'x' }, version: 1 }, auth_header(token)

      expect(last_response.status).to eq(404)
    end
  end

  describe 'DELETE /api/records/:id' do
    let!(:record) do
      SOT::MutationService.create(schema: schema, data: { 'title' => 'ToDelete' }, state: 'open', user: user)
    end

    it 'deletes a record' do
      delete_json "/api/records/#{record.id}", { version: 1 }, auth_header(token)

      expect(last_response.status).to eq(200)
      expect(json_body['message']).to include('Deleted')
    end

    it 'returns 409 on version conflict' do
      delete_json "/api/records/#{record.id}", { version: 99 }, auth_header(token)

      expect(last_response.status).to eq(409)
      expect(json_body['error']).to include('Version conflict')
    end

    it 'returns 409 on precondition failure' do
      delete_json "/api/records/#{record.id}", {
        preconditions: { 'state' => 'closed' },
        version: 1
      }, auth_header(token)

      expect(last_response.status).to eq(409)
    end

    it 'returns 404 for nonexistent record' do
      delete_json '/api/records/99999', {}, auth_header(token)

      expect(last_response.status).to eq(404)
    end
  end
end
