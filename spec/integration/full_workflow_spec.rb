require 'spec_helper'

RSpec.describe 'Full workflow', type: :api do
  let(:admin_pair) { SOT::User.create_with_token(name: 'admin', is_admin: true) }
  let(:admin) { admin_pair.first }
  let(:admin_token) { admin_pair.last }

  let(:user_pair) { SOT::User.create_with_token(name: 'dev') }
  let(:user) { user_pair.first }
  let(:user_token) { user_pair.last }

  it 'completes end-to-end: schema → create → query → update → activity → delete → audit' do
    # Step 1: Admin creates a schema
    post_json '/api/admin/schemas', {
      namespace: 'org',
      name: 'locks',
      description: 'Resource reservation locks',
      fields: [
        { 'name' => 'resource', 'type' => 'string', 'required' => true, 'description' => 'What is locked' },
        { 'name' => 'reason', 'type' => 'string', 'description' => 'Why it is locked' }
      ],
      states: [
        { 'name' => 'locked', 'description' => 'Resource is currently locked' },
        { 'name' => 'unlocked', 'description' => 'Resource is free' }
      ]
    }, auth_header(admin_token)
    expect(last_response.status).to eq(201)

    # Step 2: User creates a record
    post_json '/api/records', {
      table: 'org.locks',
      data: { 'resource' => 'staging-db', 'reason' => 'running migration' },
      state: 'locked'
    }, auth_header(user_token)
    expect(last_response.status).to eq(201)
    record_id = json_body['record']['id']

    # Step 3: Query the record
    get '/api/records/org.locks', { state: 'locked' }, auth_header(user_token)
    expect(last_response.status).to eq(200)
    expect(json_body['records'].length).to eq(1)
    expect(json_body['records'].first['data']['resource']).to eq('staging-db')

    # Step 4: Update with precondition (lock → unlock)
    patch_json "/api/records/#{record_id}", {
      state: 'unlocked',
      preconditions: { 'state' => 'locked' },
      version: 1
    }, auth_header(user_token)
    expect(last_response.status).to eq(200)
    expect(json_body['record']['state']).to eq('unlocked')
    expect(json_body['record']['version']).to eq(2)

    # Step 5: Verify precondition fails on stale state
    patch_json "/api/records/#{record_id}", {
      state: 'locked',
      preconditions: { 'state' => 'locked' },
      version: 2
    }, auth_header(user_token)
    expect(last_response.status).to eq(409)

    # Step 6: Check activity log
    get '/api/activity_log', { table: 'org.locks' }, auth_header(user_token)
    expect(last_response.status).to eq(200)
    actions = json_body['entries'].map { |e| e['action'] }
    expect(actions).to include('create', 'update')

    # Step 7: Delete the record
    delete_json "/api/records/#{record_id}", { version: 2 }, auth_header(user_token)
    expect(last_response.status).to eq(200)

    # Step 8: Verify deletion is in activity log
    get '/api/activity_log', { table: 'org.locks' }, auth_header(user_token)
    actions = json_body['entries'].map { |e| e['action'] }
    expect(actions).to include('create', 'update', 'delete')

    # Step 9: Verify record is gone
    get '/api/records/org.locks', {}, auth_header(user_token)
    expect(json_body['records']).to be_empty
  end
end
