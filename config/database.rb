require 'sequel'

module SOT
  module Database
    def self.connect(url = nil)
      url ||= if ENV['RACK_ENV'] == 'test'
                'sqlite:/'
              elsif ENV['SOT_DB_PATH']
                "sqlite://#{File.expand_path(ENV['SOT_DB_PATH'])}"
              else
                "sqlite://#{File.expand_path("../db/sot_#{ENV.fetch('RACK_ENV', 'development')}.sqlite3", __dir__)}"
              end

      db = Sequel.connect(url)

      if db.database_type == :sqlite
        db.run('PRAGMA journal_mode=WAL')
        db.run('PRAGMA busy_timeout=5000')
        db.run('PRAGMA foreign_keys=ON')
        db.run('PRAGMA synchronous=NORMAL')
      end

      db
    end
  end
end

DB = SOT::Database.connect unless defined?(DB)
