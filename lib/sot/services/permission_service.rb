module SOT
  class PermissionService
    class PermissionDenied < StandardError; end

    ACTIONS = %i[read create update delete].freeze

    def self.can?(user, schema, action)
      raise ArgumentError, "Invalid action: #{action}" unless ACTIONS.include?(action.to_sym)

      return true if user.admin?

      schema.roles_for_action(action).include?(user.role.name)
    end

    def self.authorize!(user, schema, action)
      return if can?(user, schema, action)

      raise PermissionDenied, "You don't have #{action} access to table '#{schema.full_name}'."
    end

    def self.readable_schemas(user)
      return SOT::Schema.order(:namespace, :name).all if user.admin?

      SOT::Schema.order(:namespace, :name).all.select do |s|
        s.parsed_read_roles.include?(user.role.name)
      end
    end

    def self.readable_schema_ids(user)
      readable_schemas(user).map(&:id)
    end
  end
end
