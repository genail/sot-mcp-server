require 'spec_helper'

RSpec.describe SOT::Tools::User::ListWebhooks, type: :tool do
  let(:user) { create(:user) }
  let(:admin) { create(:user, :admin) }

  before do
    SOT::Webhook.create(
      name: 'notify_slack',
      description: 'Send a Slack notification',
      url: 'https://hooks.slack.com/secret',
      http_method: 'POST',
      headers: JSON.generate({ 'Authorization' => 'Bearer secret-token' }),
      payload_template: '{"text": "{{message}}"}',
      variables: JSON.generate([{ 'name' => 'message', 'description' => 'The notification message' }]),
      allowed_roles: JSON.generate(%w[member])
    )
    SOT::Webhook.create(
      name: 'admin_only_hook',
      description: 'Admin-only webhook',
      url: 'https://internal.example.com/admin',
      http_method: 'POST',
      payload_template: '{}',
      variables: '[]',
      allowed_roles: '[]'
    )
  end

  it 'lists webhooks the user can call' do
    response = call_tool(described_class, user: user)
    text = response_text(response)

    expect(text).to include('notify_slack')
    expect(text).to include('Send a Slack notification')
    expect(text).to include('message')
    expect(text).to include('The notification message')
    expect(text).not_to include('admin_only_hook')
  end

  it 'does not expose url, headers, or method' do
    response = call_tool(described_class, user: user)
    text = response_text(response)

    expect(text).not_to include('hooks.slack.com')
    expect(text).not_to include('secret-token')
    expect(text).not_to include('Bearer')
  end

  it 'lists all webhooks for admin' do
    response = call_tool(described_class, user: admin)
    text = response_text(response)

    expect(text).to include('notify_slack')
    expect(text).to include('admin_only_hook')
  end

  it 'returns message when no webhooks available' do
    SOT::Webhook.dataset.delete
    response = call_tool(described_class, user: user)
    text = response_text(response)

    expect(text).to include('No webhooks')
  end
end
