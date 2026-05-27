require 'spec_helper'

RSpec.describe SOT::Tools::Admin::ManageWebhooks, type: :tool do
  let(:admin) { create(:user, :admin) }

  describe 'create' do
    it 'creates a webhook' do
      response = call_tool(described_class, user: admin,
        action: 'create',
        name: 'notify_slack',
        description: 'Notify Slack channel',
        url: 'https://hooks.slack.com/test',
        http_method: 'POST',
        headers: { 'Authorization' => 'Bearer token' },
        payload_template: '{"text": "{{message}}"}',
        variables: [{ 'name' => 'message', 'description' => 'The message to send' }],
        allowed_roles: %w[member]
      )

      expect(response_error?(response)).to be false
      expect(response_text(response)).to include('notify_slack')

      webhook = SOT::Webhook.first(name: 'notify_slack')
      expect(webhook).not_to be_nil
      expect(webhook.url).to eq('https://hooks.slack.com/test')
      expect(webhook.parsed_headers).to eq({ 'Authorization' => 'Bearer token' })
    end

    it 'returns error on validation failure' do
      response = call_tool(described_class, user: admin,
        action: 'create',
        name: 'bad',
        url: 'https://example.com',
        http_method: 'POST',
        payload_template: '{"text": "{{missing_var}}"}',
        variables: []
      )

      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('missing_var')
    end

    it 'requires name' do
      response = call_tool(described_class, user: admin,
        action: 'create',
        url: 'https://example.com',
        http_method: 'POST',
        payload_template: '{}',
        variables: []
      )

      expect(response_error?(response)).to be true
    end
  end

  describe 'list' do
    it 'lists all webhooks with full details' do
      SOT::Webhook.create(
        name: 'hook1', description: 'First', url: 'https://a.com', http_method: 'POST',
        payload_template: '{}', variables: '[]', allowed_roles: JSON.generate(%w[member])
      )
      SOT::Webhook.create(
        name: 'hook2', description: 'Second', url: 'https://b.com', http_method: 'GET',
        payload_template: '{}', variables: '[]'
      )

      response = call_tool(described_class, user: admin, action: 'list')
      text = response_text(response)

      expect(text).to include('hook1')
      expect(text).to include('hook2')
      expect(text).to include('https://a.com')
      expect(text).to include('https://b.com')
    end

    it 'returns message when no webhooks exist' do
      response = call_tool(described_class, user: admin, action: 'list')
      expect(response_text(response)).to include('No webhooks')
    end
  end

  describe 'update' do
    let!(:webhook) do
      SOT::Webhook.create(
        name: 'existing', description: 'Original', url: 'https://old.com', http_method: 'POST',
        payload_template: '{"text": "{{msg}}"}',
        variables: JSON.generate([{ 'name' => 'msg', 'description' => 'A message' }])
      )
    end

    it 'updates webhook fields' do
      response = call_tool(described_class, user: admin,
        action: 'update',
        name: 'existing',
        url: 'https://new.com',
        description: 'Updated description'
      )

      expect(response_error?(response)).to be false
      webhook.refresh
      expect(webhook.url).to eq('https://new.com')
      expect(webhook.description).to eq('Updated description')
    end

    it 'validates template/variable consistency on update' do
      response = call_tool(described_class, user: admin,
        action: 'update',
        name: 'existing',
        payload_template: '{"text": "{{new_var}}"}',
      )

      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('new_var')
    end

    it 'returns error when webhook not found' do
      response = call_tool(described_class, user: admin, action: 'update', name: 'nope')

      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('not found')
    end
  end

  describe 'delete' do
    it 'deletes a webhook' do
      SOT::Webhook.create(
        name: 'to_delete', url: 'https://example.com', http_method: 'POST',
        payload_template: '{}', variables: '[]'
      )

      response = call_tool(described_class, user: admin, action: 'delete', name: 'to_delete')

      expect(response_error?(response)).to be false
      expect(SOT::Webhook.first(name: 'to_delete')).to be_nil
    end

    it 'returns error when webhook not found' do
      response = call_tool(described_class, user: admin, action: 'delete', name: 'nope')

      expect(response_error?(response)).to be true
      expect(response_text(response)).to include('not found')
    end

    it 'deletes a webhook that has logs (cascade)' do
      user = create(:user)
      webhook = SOT::Webhook.create(
        name: 'used_hook', url: 'https://example.com', http_method: 'POST',
        payload_template: '{}', variables: '[]'
      )
      SOT::WebhookLog.create(
        webhook_id: webhook.id, user_id: user.id,
        variable_values: '{}', status_code: 200, success: true
      )

      response = call_tool(described_class, user: admin, action: 'delete', name: 'used_hook')

      expect(response_error?(response)).to be false
      expect(SOT::Webhook.first(name: 'used_hook')).to be_nil
      expect(SOT::WebhookLog.where(webhook_id: webhook.id).count).to eq(0)
    end
  end
end
