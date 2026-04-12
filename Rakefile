require 'sequel'
require 'sequel/extensions/migration'

namespace :db do
  desc 'Run database migrations'
  task :migrate do
    require_relative 'config/database'
    Sequel::Migrator.run(DB, 'db/migrations')
    puts "Migrations complete."
  end

  desc 'Rollback last migration'
  task :rollback do
    require_relative 'config/database'
    Sequel::Migrator.run(DB, 'db/migrations', target: Sequel::Migrator.migrator_class(DB).new(DB, 'db/migrations').current - 1)
    puts "Rollback complete."
  end

  desc 'Seed admin user'
  task :seed do
    require_relative 'config/boot'
    user, token = SOT::User.create_with_token(name: 'admin', role_name: 'admin')
    puts "Admin user created: #{user.name}"
    puts "Token (save this, it won't be shown again): #{token}"
  end

  desc 'Create a new migration file'
  task :create_migration, [:name] do |_t, args|
    name = args[:name] || raise("Usage: rake db:create_migration[name]")
    timestamp = Time.now.strftime('%Y%m%d%H%M%S')
    filename = "db/migrations/#{timestamp}_#{name}.rb"
    File.write(filename, <<~RUBY)
      Sequel.migration do
        change do
        end
      end
    RUBY
    puts "Created #{filename}"
  end
end

desc 'Run RSpec tests'
task :spec do
  sh 'bundle exec rspec'
end

desc 'Start the server'
task :server do
  sh 'bundle exec rackup -p 39482'
end

task default: :spec
