require_relative 'config/boot'

USER_TOOLS = [
  SOT::Tools::User::ListEntities,
  SOT::Tools::User::Query,
  SOT::Tools::User::Mutate,
  SOT::Tools::User::ActivityLogTool,
  SOT::Tools::User::FeedbackTool,
].freeze

ADMIN_TOOLS = [
  SOT::Tools::Admin::ManageSchema,
  SOT::Tools::Admin::ManageUsers,
  SOT::Tools::Admin::ViewFeedback,
].freeze

app = Rack::Builder.new do
  # Admin MCP — more specific path, must come first
  map '/mcp/admin' do
    use SOT::Middleware::TokenAuth
    use SOT::Middleware::AdminGate
    run SOT::RackMcpApp.new(tools: ADMIN_TOOLS)
  end

  # User MCP
  map '/mcp' do
    use SOT::Middleware::TokenAuth
    run SOT::RackMcpApp.new(tools: USER_TOOLS)
  end

  # REST API
  map '/api' do
    use SOT::Middleware::TokenAuth
    run SOT::ApiApp
  end
end

run app
