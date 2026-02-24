require 'bcrypt'
require 'securerandom'

module SOT
  class User < Sequel::Model(:_users)
    plugin :timestamps, update_on_create: true
    plugin :validation_helpers

    one_to_many :activity_logs, class: 'SOT::ActivityLog'
    one_to_many :feedbacks, class: 'SOT::Feedback'

    def validate
      super
      validates_presence [:name, :token_hash]
      validates_unique :name
    end

    def self.authenticate(token)
      return nil if token.nil? || token.empty?

      user = all.find { |u| BCrypt::Password.new(u.token_hash) == token }
      return nil if user && !user.is_active

      user
    end

    def self.create_with_token(name:, is_admin: false)
      token = SecureRandom.hex(32)
      user = create(
        name: name,
        token_hash: BCrypt::Password.create(token),
        is_admin: is_admin
      )
      [user, token]
    end
  end
end
