module SOT
  class Role < Sequel::Model(:_roles)
    plugin :timestamps, update_on_create: true
    plugin :validation_helpers

    one_to_many :users, class: 'SOT::User'

    SYSTEM_ROLES = %w[admin member].freeze

    def validate
      super
      validates_presence [:name]
      validates_unique :name
      validates_format(/\A[a-z][a-z0-9_]*\z/, :name, message: 'must be lowercase alphanumeric with underscores') if name
    end

    def system_role?
      SYSTEM_ROLES.include?(name)
    end
  end
end
