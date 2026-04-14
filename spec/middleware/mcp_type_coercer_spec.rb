require 'spec_helper'

# Request-level specs that exercise the transport-layer type coercion shim in
# RackMcpApp. These verify the workaround for the Claude Code MCP client bug
# where integer/object/boolean tool args arrive as JSON strings.
RSpec.describe 'MCP transport type coercion', type: :api do
  include Rack::Test::Methods

  def app
    Rack::Builder.new do
      map '/mcp' do
        use SOT::Middleware::TokenAuth, post_only: true
        run SOT::RackMcpApp.new(tools: [
          SOT::Tools::User::Mutate,
          SOT::Tools::User::Query,
          SOT::Tools::User::DescribeTables,
        ])
      end
    end
  end

  let(:raw_token) { 'test_token_12345' }
  let!(:user) { create(:user, raw_token: raw_token) }
  let!(:schema) { create(:table_schema, namespace: 'org', name: 'items') }
  let!(:record) do
    SOT::MutationService.create(
      schema: schema,
      data: { 'title' => 'Original', 'count' => 1 },
      user: user
    )
  end

  def post_mcp(body)
    post '/mcp', body.to_json, {
      'CONTENT_TYPE' => 'application/json',
      'HTTP_ACCEPT' => 'application/json, text/event-stream',
      'HTTP_AUTHORIZATION' => "Bearer #{raw_token}"
    }
  end

  def parse_mcp_response(rack_response)
    body = rack_response.body
    # StreamableHTTP transport may return SSE (`event: message\ndata: {...}\n\n`)
    # or plain JSON. Handle both.
    if body.start_with?('event:') || body.include?("\ndata:") || body.start_with?('data:')
      data_line = body.lines.find { |l| l.start_with?('data:') }
      JSON.parse(data_line.sub(/\Adata:\s*/, ''))
    else
      JSON.parse(body)
    end
  end

  it 'coerces stringified integers and objects to native types for tools/call' do
    post_mcp(
      jsonrpc: '2.0',
      id: 1,
      method: 'tools/call',
      params: {
        name: 'sot_mutate',
        arguments: {
          'action' => 'update',
          'record_id' => record.id.to_s,
          'version' => '1',
          'data' => '{"title":"Coerced"}'
        }
      }
    )

    expect(last_response.status).to eq(200)
    payload = parse_mcp_response(last_response)
    expect(payload).not_to have_key('error'),
      "expected success, got: #{payload.inspect}"
    content = payload.dig('result', 'content')
    expect(content).to be_an(Array)
    expect(content.first['text']).to include('Updated record')

    refreshed = SOT::Record[record.id]
    expect(refreshed.parsed_data['title']).to eq('Coerced')
  end

  it 'passes native JSON types through unchanged' do
    post_mcp(
      jsonrpc: '2.0',
      id: 2,
      method: 'tools/call',
      params: {
        name: 'sot_mutate',
        arguments: {
          'action' => 'update',
          'record_id' => record.id,
          'version' => 1,
          'data' => { 'title' => 'Native' }
        }
      }
    )

    expect(last_response.status).to eq(200)
    payload = parse_mcp_response(last_response)
    expect(payload).not_to have_key('error'),
      "expected success, got: #{payload.inspect}"

    refreshed = SOT::Record[record.id]
    expect(refreshed.parsed_data['title']).to eq('Native')
  end

  it 'does not coerce a non-numeric string into an integer' do
    post_mcp(
      jsonrpc: '2.0',
      id: 3,
      method: 'tools/call',
      params: {
        name: 'sot_mutate',
        arguments: {
          'action' => 'update',
          'record_id' => 'abc',
          'version' => '1',
          'data' => { 'title' => 'Hi' }
        }
      }
    )

    payload = parse_mcp_response(last_response)
    # Must surface a validation-style error rather than quietly succeeding.
    if payload.key?('error')
      expect(payload['error']['message'].to_s.downcase).to match(/invalid|type|integer|argument/)
    else
      content = payload.dig('result', 'content') || []
      combined = content.map { |c| c['text'] }.join(' ')
      expect(combined.downcase).to match(/invalid|not found|error/)
    end
  end

  it 'does not coerce nested string-looking-like-number values inside object args' do
    post_mcp(
      jsonrpc: '2.0',
      id: 4,
      method: 'tools/call',
      params: {
        name: 'sot_mutate',
        arguments: {
          'action' => 'update',
          'record_id' => record.id,
          'version' => 1,
          # top-level `data` is an object; its nested `count` value is a string
          # that happens to look like a number. It must remain a string.
          'data' => { 'count' => '42' }
        }
      }
    )

    expect(last_response.status).to eq(200)
    payload = parse_mcp_response(last_response)
    expect(payload).not_to have_key('error'),
      "expected success, got: #{payload.inspect}"

    refreshed = SOT::Record[record.id]
    expect(refreshed.parsed_data['count']).to eq('42')
    expect(refreshed.parsed_data['count']).to be_a(String)
  end

  it 'passes notification (no id) requests through untouched' do
    # A notification has no id and expects no response body per JSON-RPC spec.
    # We simply ensure the shim doesn't explode on it.
    post_mcp(
      jsonrpc: '2.0',
      method: 'notifications/initialized',
      params: {}
    )

    # Accept either 200 or 202; what matters is no 500 from the shim.
    expect(last_response.status).to be < 500
  end
end
