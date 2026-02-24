require 'spec_helper'

RSpec.describe 'GET /api/schemas', type: :api do
  let(:user) { SOT::User.create_with_token(name: 'api_user') }
  let(:token) { user.last }

  before do
    create(:table_schema, :stateful, namespace: 'org', name: 'locks')
    create(:table_schema, namespace: 'org', name: 'docs')
  end

  it 'lists all schemas' do
    get '/api/schemas', {}, auth_header(token)

    expect(last_response.status).to eq(200)
    schemas = json_body['schemas']
    expect(schemas.length).to eq(2)
    expect(schemas.map { |s| s['full_name'] }).to contain_exactly('org.locks', 'org.docs')
  end

  it 'filters by namespace' do
    create(:table_schema, namespace: 'project', name: 'tasks')

    get '/api/schemas', { namespace: 'project' }, auth_header(token)

    expect(last_response.status).to eq(200)
    schemas = json_body['schemas']
    expect(schemas.length).to eq(1)
    expect(schemas.first['full_name']).to eq('project.tasks')
  end

  it 'requires authentication' do
    get '/api/schemas'

    expect(last_response.status).to eq(401)
  end
end
