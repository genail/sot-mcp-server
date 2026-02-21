module SOT
  class UserService
    def self.create(name:, is_admin: false)
      User.create_with_token(name: name, is_admin: is_admin)
    end

    def self.update(user, **attrs)
      user.update(attrs)
      user
    end

    def self.delete(user)
      user.destroy
    end

    def self.list
      User.order(:name).all
    end

    def self.find_by_name(name)
      User.first(name: name)
    end

    def self.regenerate_token(user)
      token = SecureRandom.hex(32)
      user.update(token_hash: BCrypt::Password.create(token))
      [user, token]
    end
  end
end
