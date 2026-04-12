require 'bcrypt'
require 'securerandom'

module SOT
  class User < Sequel::Model(:_users)
    plugin :timestamps, update_on_create: true
    plugin :validation_helpers

    many_to_one :role, class: 'SOT::Role'
    one_to_many :activity_logs, class: 'SOT::ActivityLog'
    one_to_many :feedbacks, class: 'SOT::Feedback'

    def validate
      super
      validates_presence [:name, :token_hash, :role_id]
      validates_unique :name
    end

    def admin?
      role&.name == 'admin'
    end

    def self.authenticate(token)
      return nil if token.nil? || token.empty?

      user = all.find { |u| BCrypt::Password.new(u.token_hash) == token }
      return nil if user && !user.is_active

      user
    end

    def self.create_with_token(name:, role_name: 'member')
      role = SOT::Role.first(name: role_name)
      raise ArgumentError, "Role '#{role_name}' not found" unless role

      token = SecureRandom.hex(32)
      user = create(
        name: name,
        token_hash: BCrypt::Password.create(token),
        is_admin: role_name == 'admin',
        role_id: role.id
      )
      [user, token]
    end
  end
end
