require 'spec_helper'

RSpec.describe SOT::Tools::Admin::WebhookLogs, type: :tool do
  let(:admin) { create(:user, :admin) }
  let(:user) { create(:user) }

  let!(:webhook) do
    SOT::Webhook.create(
      name: 'test_hook', url: 'https://example.com', http_method: 'POST',
      payload_template: '{}', variables: '[]'
    )
  end

  before do
    SOT::WebhookLog.create(
      webhook_id: webhook.id, user_id: user.id,
      variable_values: JSON.generate({ 'key' => 'val' }),
      status_code: 200, response_body: '{"ok":true}', success: true
    )
    SOT::WebhookLog.create(
      webhook_id: webhook.id, user_id: user.id,
      variable_values: '{}',
      status_code: 500, response_body: 'error', success: false,
      error_message: 'Server error'
    )
  end

  it 'lists all webhook logs' do
    response = call_tool(described_class, user: admin)
    text = response_text(response)

    expect(text).to include('test_hook')
    expect(text).to include('200')
    expect(text).to include('500')
  end

  it 'filters by webhook name' do
    other = SOT::Webhook.create(
      name: 'other_hook', url: 'https://example.com', http_method: 'POST',
      payload_template: '{}', variables: '[]'
    )
    SOT::WebhookLog.create(
      webhook_id: other.id, user_id: user.id,
      variable_values: '{}', status_code: 200, success: true
    )

    response = call_tool(described_class, user: admin, webhook_name: 'test_hook')
    text = response_text(response)

    expect(text).to include('test_hook')
    expect(text).not_to include('other_hook')
  end

  it 'shows response body in logs' do
    response = call_tool(described_class, user: admin)
    text = response_text(response)

    expect(text).to include('{"ok":true}')
  end

  it 'returns message when no logs exist' do
    SOT::WebhookLog.dataset.delete
    response = call_tool(described_class, user: admin)

    expect(response_text(response)).to include('No webhook logs')
  end
end
