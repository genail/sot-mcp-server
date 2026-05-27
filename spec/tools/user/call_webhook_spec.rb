require 'spec_helper'
require 'net/http'

RSpec.describe SOT::Tools::User::CallWebhook, type: :tool do
  let(:user) { create(:user) }
  let(:admin) { create(:user, :admin) }

  let!(:webhook) do
    SOT::Webhook.create(
      name: 'notify_slack',
      description: 'Send a Slack notification',
      url: 'https://hooks.slack.com/test',
      http_method: 'POST',
      payload_template: '{"text": "{{message}}"}',
      variables: JSON.generate([{ 'name' => 'message', 'description' => 'The notification message' }]),
      allowed_roles: JSON.generate(%w[member])
    )
  end

  let!(:admin_only_webhook) do
    SOT::Webhook.create(
      name: 'admin_hook',
      description: 'Admin-only',
      url: 'https://example.com/admin',
      http_method: 'POST',
      payload_template: '{}',
      variables: '[]',
      allowed_roles: '[]'
    )
  end

  def stub_http_success
    response = instance_double(Net::HTTPResponse, code: '200', body: '{"ok":true}')
    http = instance_double(Net::HTTP)
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:use_ssl=)
    allow(http).to receive(:open_timeout=)
    allow(http).to receive(:read_timeout=)
    allow(http).to receive(:request).and_return(response)
  end

  it 'calls webhook and returns success' do
    stub_http_success
    response = call_tool(described_class, user: user,
      name: 'notify_slack',
      variable_values: { 'message' => 'Hello world' }
    )
    text = response_text(response)

    expect(response_error?(response)).to be false
    expect(text).to include('200')
    expect(text).not_to include('hooks.slack.com')
  end

  it 'returns error when webhook not found' do
    response = call_tool(described_class, user: user, name: 'nonexistent', variable_values: {})

    expect(response_error?(response)).to be true
    expect(response_text(response)).to include('not found')
  end

  it 'returns error when user lacks permission' do
    response = call_tool(described_class, user: user, name: 'admin_hook', variable_values: {})

    expect(response_error?(response)).to be true
    expect(response_text(response)).to include('not found')
  end

  it 'allows admin to call any webhook' do
    stub_http_success
    response = call_tool(described_class, user: admin, name: 'admin_hook', variable_values: {})

    expect(response_error?(response)).to be false
  end

  it 'returns error on missing variable values' do
    response = call_tool(described_class, user: user, name: 'notify_slack', variable_values: {})

    expect(response_error?(response)).to be true
    expect(response_text(response)).to include('message')
  end

  it 'does not expose response body to user' do
    stub_http_success
    response = call_tool(described_class, user: user,
      name: 'notify_slack',
      variable_values: { 'message' => 'test' }
    )
    text = response_text(response)

    expect(text).not_to include('{"ok":true}')
    expect(text).not_to include('"ok"')
  end
end
