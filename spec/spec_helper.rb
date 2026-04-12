ENV['RACK_ENV'] = 'test'

require 'sequel'
require 'sequel/extensions/migration'
require 'rspec'
require 'rack/test'
require 'factory_bot'
require 'database_cleaner/sequel'

# Connect to in-memory SQLite for tests
DB = Sequel.sqlite
DB.run('PRAGMA foreign_keys=ON')

# Run migrations
Sequel::Migrator.run(DB, File.expand_path('../db/migrations', __dir__))

# Load models
require_relative '../lib/sot/models/role'
require_relative '../lib/sot/models/user'
require_relative '../lib/sot/models/schema'
require_relative '../lib/sot/models/record'
require_relative '../lib/sot/models/activity_log'
require_relative '../lib/sot/models/feedback'

# Load services
require_relative '../lib/sot/services/error_formatter'
require_relative '../lib/sot/services/type_coercion'
require_relative '../lib/sot/services/schema_service'
require_relative '../lib/sot/services/query_service'
require_relative '../lib/sot/services/mutation_service'
require_relative '../lib/sot/services/permission_service'
require_relative '../lib/sot/services/snippet_service'
require_relative '../lib/sot/services/user_service'

# Load MCP tools (conditionally)
require 'mcp'
Dir[File.join(__dir__, '..', 'lib', 'sot', 'tools', '**', '*.rb')].sort.each do |f|
  require f
end

# Load middleware
require_relative '../lib/sot/middleware/token_auth'
require_relative '../lib/sot/middleware/admin_gate'

# Load apps
require_relative '../lib/sot/rack_mcp_app'
require_relative '../lib/sot/api_app'
require_relative '../lib/sot/install_app'

# Load support files
Dir[File.join(__dir__, 'support', '**', '*.rb')].sort.each { |f| require f }
Dir[File.join(__dir__, 'factories', '**', '*.rb')].sort.each { |f| require f }

# Configure FactoryBot to work with Sequel (no save! method)
FactoryBot.define do
  to_create { |instance| instance.save }
end

RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods

  config.before(:suite) do
    DatabaseCleaner[:sequel].strategy = :truncation
  end

  config.before(:each) do
    DatabaseCleaner[:sequel].start
    # Ensure system roles exist after truncation
    SOT::Role.find_or_create(name: 'admin') { |r| r.description = 'Admin role' }
    SOT::Role.find_or_create(name: 'member') { |r| r.description = 'Default role' }
  end

  config.after(:each) do
    DB.run('PRAGMA foreign_keys=OFF')
    DatabaseCleaner[:sequel].clean
    DB.run('PRAGMA foreign_keys=ON')
  end

  config.order = :random
end
