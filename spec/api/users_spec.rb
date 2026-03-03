require 'spec_helper'

RSpec.describe 'GET /api/users', type: :api do
  let(:user) { SOT::User.create_with_token(name: 'api_user') }
  let(:token) { user.last }

  before do
    SOT::User.create_with_token(name: 'Alice')
    SOT::User.create_with_token(name: 'Bob')
  end

  it 'lists active users with id and name' do
    get '/api/users', {}, auth_header(token)

    expect(last_response.status).to eq(200)
    users = json_body['users']
    expect(users.length).to eq(3)
    expect(users).to all(include('id', 'name'))
    expect(users.map { |u| u['name'] }).to contain_exactly('Alice', 'Bob', 'api_user')
  end

  it 'excludes inactive users' do
    inactive = SOT::User.first(name: 'Bob')
    inactive.update(is_active: false)

    get '/api/users', {}, auth_header(token)

    expect(last_response.status).to eq(200)
    users = json_body['users']
    expect(users.map { |u| u['name'] }).to contain_exactly('Alice', 'api_user')
  end

  it 'requires authentication' do
    get '/api/users'

    expect(last_response.status).to eq(401)
  end
end
