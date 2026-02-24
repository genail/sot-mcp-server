require 'spec_helper'

RSpec.describe 'GET /api/activity_log', type: :api do
  let(:user_pair) { SOT::User.create_with_token(name: 'api_user') }
  let(:user) { user_pair.first }
  let(:token) { user_pair.last }
  let!(:schema) { create(:table_schema, :stateful, namespace: 'org', name: 'locks') }

  before do
    record = SOT::MutationService.create(schema: schema, data: { 'title' => 'Lock A' }, state: 'open', user: user)
    SOT::MutationService.update(record: record, state: 'closed', preconditions: { 'state' => 'open' }, user: user)
  end

  it 'returns activity entries' do
    get '/api/activity_log', {}, auth_header(token)

    expect(last_response.status).to eq(200)
    entries = json_body['entries']
    expect(entries.length).to eq(2)
    expect(entries.map { |e| e['action'] }).to contain_exactly('create', 'update')
  end

  it 'filters by table' do
    get '/api/activity_log', { table: 'org.locks' }, auth_header(token)

    expect(last_response.status).to eq(200)
    expect(json_body['entries'].length).to eq(2)
  end

  it 'filters by action' do
    get '/api/activity_log', { action: 'create' }, auth_header(token)

    expect(last_response.status).to eq(200)
    expect(json_body['entries'].length).to eq(1)
    expect(json_body['entries'].first['action']).to eq('create')
  end

  it 'returns 404 for unknown table' do
    get '/api/activity_log', { table: 'nonexistent' }, auth_header(token)

    expect(last_response.status).to eq(404)
  end

  it 'requires authentication' do
    get '/api/activity_log'

    expect(last_response.status).to eq(401)
  end
end
