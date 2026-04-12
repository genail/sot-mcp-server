ENV['RACK_ENV'] ||= 'development'

require_relative 'database'
require 'sequel/extensions/migration'

# Run pending migrations
Sequel::Migrator.run(DB, File.expand_path('../db/migrations', __dir__))

# Models
require_relative '../lib/sot/models/role'
require_relative '../lib/sot/models/user'
require_relative '../lib/sot/models/schema'
require_relative '../lib/sot/models/record'
require_relative '../lib/sot/models/activity_log'
require_relative '../lib/sot/models/feedback'

# Services
require_relative '../lib/sot/services/error_formatter'
require_relative '../lib/sot/services/type_coercion'
require_relative '../lib/sot/services/schema_service'
require_relative '../lib/sot/services/query_service'
require_relative '../lib/sot/services/mutation_service'
require_relative '../lib/sot/services/permission_service'
require_relative '../lib/sot/services/user_service'

# MCP Tools
require 'mcp'
require_relative '../lib/sot/tools/user/describe_tables'
require_relative '../lib/sot/tools/user/query'
require_relative '../lib/sot/tools/user/mutate'
require_relative '../lib/sot/tools/user/activity_log'
require_relative '../lib/sot/tools/user/feedback'
require_relative '../lib/sot/tools/user/list_users'
require_relative '../lib/sot/tools/user/whoami'
require_relative '../lib/sot/tools/admin/manage_schema'
require_relative '../lib/sot/tools/admin/manage_roles'
require_relative '../lib/sot/tools/admin/manage_users'
require_relative '../lib/sot/tools/admin/view_feedback'

# Middleware
require_relative '../lib/sot/middleware/downcase_headers'
require_relative '../lib/sot/middleware/token_auth'
require_relative '../lib/sot/middleware/admin_gate'

# Rack apps
require_relative '../lib/sot/rack_mcp_app'
require_relative '../lib/sot/api_app'
require_relative '../lib/sot/install_app'
