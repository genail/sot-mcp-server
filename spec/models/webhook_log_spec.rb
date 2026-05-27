require 'spec_helper'

RSpec.describe SOT::WebhookLog do
  let(:webhook) do
    SOT::Webhook.create(
      name: 'test_hook',
      url: 'https://example.com/hook',
      http_method: 'POST',
      payload_template: '{}',
      variables: '[]'
    )
  end

  let(:user) { create(:user) }

  describe 'associations' do
    it 'belongs to webhook' do
      log = SOT::WebhookLog.create(
        webhook_id: webhook.id,
        user_id: user.id,
        variable_values: '{}',
        status_code: 200,
        success: true
      )
      expect(log.webhook).to eq(webhook)
    end

    it 'belongs to user' do
      log = SOT::WebhookLog.create(
        webhook_id: webhook.id,
        user_id: user.id,
        variable_values: '{}',
        status_code: 200,
        success: true
      )
      expect(log.user).to eq(user)
    end
  end

  describe '#parsed_variable_values' do
    it 'returns parsed JSON' do
      log = SOT::WebhookLog.create(
        webhook_id: webhook.id,
        user_id: user.id,
        variable_values: JSON.generate({ 'user_name' => 'Alice' }),
        status_code: 200,
        success: true
      )
      expect(log.parsed_variable_values).to eq({ 'user_name' => 'Alice' })
    end
  end
end
