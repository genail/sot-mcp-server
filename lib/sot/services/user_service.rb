module SOT
  class UserService
    RENAME_BATCH_SIZE = 100

    def self.create(name:, role_name: 'member')
      User.create_with_token(name: name, role_name: role_name)
    end

    def self.update(user, **attrs)
      user.update(attrs)
      user
    end

    def self.rename(user, new_name:, admin_user:)
      old_name = user.name
      raise ArgumentError, "new name cannot be blank" if new_name.nil? || new_name.strip.empty?
      raise ArgumentError, "new name is the same as current name" if new_name == old_name

      existing = User.first(name: new_name)
      raise ArgumentError, "a user named '#{new_name}' already exists" if existing

      # Update the user record first
      user.update(name: new_name)

      # Cascade: update all user-type fields referencing the old name
      cascade_rename_in_records(old_name, new_name, admin_user)

      user
    end

    def self.deactivate(user)
      user.update(is_active: false)
      user
    end

    def self.activate(user)
      user.update(is_active: true)
      user
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

    class << self
      private

      def cascade_rename_in_records(old_name, new_name, admin_user)
        # Find all schemas with user-type fields
        schemas_with_user_fields = Schema.all.select do |schema|
          schema.parsed_fields.any? { |f| f['type'] == 'user' }
        end

        return if schemas_with_user_fields.empty?

        schemas_with_user_fields.each do |schema|
          user_fields = schema.parsed_fields.select { |f| f['type'] == 'user' }.map { |f| f['name'] }

          # Collect candidate record IDs (read-only, no lock needed)
          record_ids = Record.where(schema_id: schema.id).select_map(:id)

          # Process in batches to avoid long write locks
          record_ids.each_slice(RENAME_BATCH_SIZE) do |batch_ids|
            DB.transaction(mode: :immediate) do
              batch_ids.each do |record_id|
                # Re-fetch inside transaction for atomicity
                fresh = Record.where(id: record_id).first
                next unless fresh

                before_data = fresh.parsed_data
                after_data = before_data.dup
                changed = false

                user_fields.each do |field_name|
                  if after_data[field_name] == old_name
                    after_data[field_name] = new_name
                    changed = true
                  end
                end

                if changed
                  fresh.update(
                    data: JSON.generate(after_data),
                    version: fresh.current_version + 1
                  )

                  ActivityLog.create(
                    user_id: admin_user.id,
                    record_id: fresh.id,
                    schema_id: schema.id,
                    action: 'update',
                    changes: JSON.generate({
                      before: { data: before_data, state: fresh.state },
                      after: { data: after_data, state: fresh.state }
                    })
                  )
                end
              end
            end
          end
        end
      end
    end
  end
end
