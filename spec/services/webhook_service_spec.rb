require 'spec_helper'
require 'net/http'

RSpec.describe SOT::WebhookService do
  let(:user) { create(:user) }
  let(:admin) { create(:user, :admin) }

  describe '.render_template' do
    it 'replaces all variable placeholders' do
      template = '{"text": "{{user_name}} reported {{issue}}"}'
      values = { 'user_name' => 'Alice', 'issue' => 'Bug #42' }
      result = described_class.render_template(template, values)
      expect(result).to eq('{"text": "Alice reported Bug #42"}')
    end

    it 'handles duplicate placeholders' do
      template = '{"a": "{{x}}", "b": "{{x}}"}'
      values = { 'x' => 'hello' }
      result = described_class.render_template(template, values)
      expect(result).to eq('{"a": "hello", "b": "hello"}')
    end

    it 'raises on missing variable values' do
      template = '{"text": "{{user_name}}"}'
      values = {}
      expect { described_class.render_template(template, values) }
        .to raise_error(SOT::WebhookService::ValidationError, /user_name/)
    end
  end

  describe '.can_call?' do
    it 'returns true for admin regardless of allowed_roles' do
      webhook = SOT::Webhook.create(
        name: 'admin_only', url: 'https://example.com', http_method: 'POST',
        payload_template: '{}', variables: '[]', allowed_roles: '[]'
      )
      expect(described_class.can_call?(admin, webhook)).to be true
    end

    it 'returns true when user role is in allowed_roles' do
      webhook = SOT::Webhook.create(
        name: 'for_members', url: 'https://example.com', http_method: 'POST',
        payload_template: '{}', variables: '[]',
        allowed_roles: JSON.generate(%w[member])
      )
      expect(described_class.can_call?(user, webhook)).to be true
    end

    it 'returns false when user role is not in allowed_roles' do
      webhook = SOT::Webhook.create(
        name: 'restricted', url: 'https://example.com', http_method: 'POST',
        payload_template: '{}', variables: '[]', allowed_roles: '[]'
      )
      expect(described_class.can_call?(user, webhook)).to be false
    end
  end

  describe '.call_webhook' do
    def stub_http_response(status:, body: '')
      response = instance_double(Net::HTTPResponse, code: status.to_s, body: body)
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:request).and_return(response)
      { http: http, response: response }
    end

    it 'makes HTTP call with rendered template and logs result' do
      stubs = stub_http_response(status: 200, body: '{"ok": true}')

      webhook = SOT::Webhook.create(
        name: 'test_hook', url: 'https://example.com/hook', http_method: 'POST',
        payload_template: '{"msg": "{{greeting}}"}',
        variables: JSON.generate([{ 'name' => 'greeting', 'description' => 'A greeting' }]),
        allowed_roles: JSON.generate(%w[member])
      )

      result = described_class.call_webhook(webhook: webhook, user: user, variable_values: { 'greeting' => 'Hello' })

      expect(result[:success]).to be true
      expect(result[:status_code]).to eq(200)

      expect(stubs[:http]).to have_received(:request) do |req|
        expect(req.body).to eq('{"msg": "Hello"}')
      end

      log = SOT::WebhookLog.last
      expect(log.webhook_id).to eq(webhook.id)
      expect(log.user_id).to eq(user.id)
      expect(log.success).to be true
      expect(log.status_code).to eq(200)
    end

    it 'sends custom headers' do
      stubs = stub_http_response(status: 200)

      webhook = SOT::Webhook.create(
        name: 'with_headers', url: 'https://example.com/hook', http_method: 'POST',
        payload_template: '{}', variables: '[]',
        headers: JSON.generate({ 'X-Custom' => 'test-value' }),
        allowed_roles: JSON.generate(%w[member])
      )

      described_class.call_webhook(webhook: webhook, user: user, variable_values: {})

      expect(stubs[:http]).to have_received(:request) do |req|
        expect(req['X-Custom']).to eq('test-value')
      end
    end

    it 'logs failure on non-2xx response' do
      stub_http_response(status: 500, body: 'Internal Server Error')

      webhook = SOT::Webhook.create(
        name: 'failing_hook', url: 'https://example.com/fail', http_method: 'POST',
        payload_template: '{}', variables: '[]',
        allowed_roles: JSON.generate(%w[member])
      )

      result = described_class.call_webhook(webhook: webhook, user: user, variable_values: {})

      expect(result[:success]).to be false
      expect(result[:status_code]).to eq(500)

      log = SOT::WebhookLog.last
      expect(log.success).to be false
      expect(log.status_code).to eq(500)
    end

    it 'handles connection errors gracefully' do
      allow(Net::HTTP).to receive(:new).and_raise(Errno::ECONNREFUSED)

      webhook = SOT::Webhook.create(
        name: 'unreachable', url: 'https://localhost:1/nope', http_method: 'POST',
        payload_template: '{}', variables: '[]',
        allowed_roles: JSON.generate(%w[member])
      )

      result = described_class.call_webhook(webhook: webhook, user: user, variable_values: {})

      expect(result[:success]).to be false
      expect(result[:status_code]).to be_nil
      expect(result[:error]).to be_a(String)

      log = SOT::WebhookLog.last
      expect(log.success).to be false
      expect(log.error_message).not_to be_nil
    end

    it 'supports GET method' do
      stubs = stub_http_response(status: 200)

      webhook = SOT::Webhook.create(
        name: 'get_hook', url: 'https://example.com/get', http_method: 'GET',
        payload_template: '{}', variables: '[]',
        allowed_roles: JSON.generate(%w[member])
      )

      result = described_class.call_webhook(webhook: webhook, user: user, variable_values: {})
      expect(result[:success]).to be true

      expect(stubs[:http]).to have_received(:request) do |req|
        expect(req).to be_a(Net::HTTP::Get)
      end
    end

    it 'raises ValidationError on missing variable values' do
      webhook = SOT::Webhook.create(
        name: 'needs_vars', url: 'https://example.com/hook', http_method: 'POST',
        payload_template: '{"x": "{{foo}}"}',
        variables: JSON.generate([{ 'name' => 'foo', 'description' => 'A foo' }]),
        allowed_roles: JSON.generate(%w[member])
      )

      expect {
        described_class.call_webhook(webhook: webhook, user: user, variable_values: {})
      }.to raise_error(SOT::WebhookService::ValidationError)
    end
  end
end
