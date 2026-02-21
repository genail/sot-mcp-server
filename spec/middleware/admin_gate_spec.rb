require 'spec_helper'

RSpec.describe SOT::Middleware::AdminGate do
  let(:inner_app) do
    ->(env) { [200, { 'content-type' => 'text/plain' }, ['admin_ok']] }
  end
  let(:app) { described_class.new(inner_app) }

  def make_request(user: nil)
    env = Rack::MockRequest.env_for('/')
    env['sot.current_user'] = user
    app.call(env)
  end

  describe 'with admin user' do
    it 'passes through to inner app' do
      admin = create(:user, :admin)
      status, _headers, body = make_request(user: admin)

      expect(status).to eq(200)
      expect(body.first).to eq('admin_ok')
    end
  end

  describe 'with non-admin user' do
    it 'returns 403' do
      user = create(:user)
      status, headers, body = make_request(user: user)

      expect(status).to eq(403)
      expect(headers['content-type']).to eq('application/json')
      expect(body.first).to include('Admin access required')
    end
  end

  describe 'with no user' do
    it 'returns 403' do
      status, _headers, body = make_request

      expect(status).to eq(403)
      expect(body.first).to include('Admin access required')
    end
  end
end
