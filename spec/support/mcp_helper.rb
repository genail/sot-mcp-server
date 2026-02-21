module McpHelper
  def call_tool(tool_class, user: nil, **params)
    user ||= create(:user)
    tool_class.call(server_context: { user: user }, **params)
  end

  def response_text(response)
    response.content&.first&.dig(:text) || ''
  end

  def response_error?(response)
    response.error?
  end
end

RSpec.configure do |config|
  config.include McpHelper, type: :tool
end
