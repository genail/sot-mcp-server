require 'spec_helper'

RSpec.describe SOT::Webhook do
  describe 'validations' do
    it 'requires name' do
      webhook = SOT::Webhook.new(
        description: 'Test',
        url: 'https://example.com',
        http_method: 'POST',
        payload_template: '{}',
        variables: '[]'
      )
      expect(webhook.valid?).to be false
      expect(webhook.errors[:name]).not_to be_empty
    end

    it 'requires unique name' do
      SOT::Webhook.create(
        name: 'notify_slack',
        description: 'Notify Slack',
        url: 'https://hooks.slack.com/test',
        http_method: 'POST',
        payload_template: '{"text": "hello"}',
        variables: '[]'
      )
      webhook = SOT::Webhook.new(name: 'notify_slack', url: 'https://example.com', http_method: 'POST', payload_template: '{}', variables: '[]')
      expect(webhook.valid?).to be false
    end

    it 'requires url' do
      webhook = SOT::Webhook.new(name: 'test', http_method: 'POST', payload_template: '{}', variables: '[]')
      expect(webhook.valid?).to be false
      expect(webhook.errors[:url]).not_to be_empty
    end

    it 'requires method' do
      webhook = SOT::Webhook.new(name: 'test', url: 'https://example.com', payload_template: '{}', variables: '[]')
      expect(webhook.valid?).to be false
      expect(webhook.errors[:http_method]).not_to be_empty
    end

    it 'requires payload_template' do
      webhook = SOT::Webhook.new(name: 'test', url: 'https://example.com', http_method: 'POST', variables: '[]')
      expect(webhook.valid?).to be false
      expect(webhook.errors[:payload_template]).not_to be_empty
    end

    it 'requires variables' do
      webhook = SOT::Webhook.new(name: 'test', url: 'https://example.com', http_method: 'POST', payload_template: '{}')
      expect(webhook.valid?).to be false
      expect(webhook.errors[:variables]).not_to be_empty
    end

    it 'validates method is a known HTTP method' do
      webhook = SOT::Webhook.new(
        name: 'test', url: 'https://example.com', http_method: 'INVALID',
        payload_template: '{}', variables: '[]'
      )
      expect(webhook.valid?).to be false
      expect(webhook.errors[:http_method]).not_to be_empty
    end

    it 'accepts valid HTTP methods' do
      %w[GET POST PUT PATCH DELETE].each do |m|
        webhook = SOT::Webhook.new(
          name: "test_#{m.downcase}", url: 'https://example.com', http_method: m,
          payload_template: '{}', variables: '[]'
        )
        expect(webhook.valid?).to eq(true), "Expected #{m} to be valid but got errors: #{webhook.errors.full_messages}"
      end
    end

    it 'validates template variables match variable definitions' do
      webhook = SOT::Webhook.new(
        name: 'test', url: 'https://example.com', http_method: 'POST',
        payload_template: '{"text": "{{user_name}} did {{action}}"}',
        variables: JSON.generate([{ 'name' => 'user_name', 'description' => 'The user' }])
      )
      expect(webhook.valid?).to be false
      expect(webhook.errors[:variables].first).to include('action')
    end

    it 'validates variable definitions match template variables' do
      webhook = SOT::Webhook.new(
        name: 'test', url: 'https://example.com', http_method: 'POST',
        payload_template: '{"text": "{{user_name}}"}',
        variables: JSON.generate([
          { 'name' => 'user_name', 'description' => 'The user' },
          { 'name' => 'extra_var', 'description' => 'Not in template' }
        ])
      )
      expect(webhook.valid?).to be false
      expect(webhook.errors[:variables].first).to include('extra_var')
    end

    it 'passes when template and variables match' do
      webhook = SOT::Webhook.new(
        name: 'test', url: 'https://example.com', http_method: 'POST',
        payload_template: '{"text": "{{user_name}} did {{action}}"}',
        variables: JSON.generate([
          { 'name' => 'user_name', 'description' => 'The user' },
          { 'name' => 'action', 'description' => 'What happened' }
        ])
      )
      expect(webhook.valid?).to be true
    end

    it 'validates variables entries have name and description' do
      webhook = SOT::Webhook.new(
        name: 'test', url: 'https://example.com', http_method: 'POST',
        payload_template: '{"text": "{{foo}}"}',
        variables: JSON.generate([{ 'name' => 'foo' }])
      )
      expect(webhook.valid?).to be false
      expect(webhook.errors[:variables].first).to include('description')
    end
  end

  describe '#parsed_variables' do
    it 'returns parsed JSON array' do
      webhook = SOT::Webhook.create(
        name: 'test', url: 'https://example.com', http_method: 'POST',
        payload_template: '{"text": "{{user}}"}',
        variables: JSON.generate([{ 'name' => 'user', 'description' => 'The user' }])
      )
      expect(webhook.parsed_variables).to eq([{ 'name' => 'user', 'description' => 'The user' }])
    end
  end

  describe '#parsed_headers' do
    it 'returns parsed JSON hash' do
      webhook = SOT::Webhook.create(
        name: 'test', url: 'https://example.com', http_method: 'POST',
        payload_template: '{}', variables: '[]',
        headers: JSON.generate({ 'Authorization' => 'Bearer abc' })
      )
      expect(webhook.parsed_headers).to eq({ 'Authorization' => 'Bearer abc' })
    end

    it 'returns empty hash when nil' do
      webhook = SOT::Webhook.create(
        name: 'test', url: 'https://example.com', http_method: 'POST',
        payload_template: '{}', variables: '[]'
      )
      expect(webhook.parsed_headers).to eq({})
    end
  end

  describe '#parsed_allowed_roles' do
    it 'returns parsed JSON array' do
      webhook = SOT::Webhook.create(
        name: 'test', url: 'https://example.com', http_method: 'POST',
        payload_template: '{}', variables: '[]',
        allowed_roles: JSON.generate(%w[member])
      )
      expect(webhook.parsed_allowed_roles).to eq(%w[member])
    end

    it 'returns empty array when nil' do
      webhook = SOT::Webhook.create(
        name: 'test', url: 'https://example.com', http_method: 'POST',
        payload_template: '{}', variables: '[]'
      )
      expect(webhook.parsed_allowed_roles).to eq([])
    end
  end

  describe '#template_placeholders' do
    it 'extracts variable names from template' do
      webhook = SOT::Webhook.new(
        payload_template: '{"msg": "{{user}} reported {{issue}}"}'
      )
      expect(webhook.template_placeholders).to contain_exactly('user', 'issue')
    end

    it 'handles duplicate placeholders' do
      webhook = SOT::Webhook.new(
        payload_template: '{"a": "{{x}}", "b": "{{x}}"}'
      )
      expect(webhook.template_placeholders).to eq(%w[x])
    end
  end
end
