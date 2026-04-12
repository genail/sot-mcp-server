Sequel.migration do
  up do
    create_table(:_roles) do
      primary_key :id
      String :name, null: false, unique: true
      String :description, text: true
      DateTime :created_at, null: false
      DateTime :updated_at, null: false
    end

    now = Time.now
    admin_id = DB[:_roles].insert(name: 'admin', description: 'Full access to all tables and admin tools', created_at: now, updated_at: now)
    member_id = DB[:_roles].insert(name: 'member', description: 'Default role for regular users', created_at: now, updated_at: now)

    alter_table(:_users) do
      add_foreign_key :role_id, :_roles
    end

    DB[:_users].where(is_admin: true).update(role_id: admin_id)
    DB[:_users].where(is_admin: false).update(role_id: member_id)

    alter_table(:_users) do
      set_column_not_null :role_id
    end

    alter_table(:_users) do
      add_index :role_id
    end
  end

  down do
    alter_table(:_users) do
      drop_index :role_id
      drop_column :role_id
    end

    drop_table(:_roles)
  end
end
