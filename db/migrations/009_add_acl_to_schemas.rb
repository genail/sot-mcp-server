Sequel.migration do
  up do
    alter_table(:_schemas) do
      add_column :read_roles, String, text: true, null: false, default: '[]'
      add_column :create_roles, String, text: true, null: false, default: '[]'
      add_column :update_roles, String, text: true, null: false, default: '[]'
      add_column :delete_roles, String, text: true, null: false, default: '[]'
    end

    DB[:_schemas].update(
      read_roles: '["member"]',
      create_roles: '["member"]',
      update_roles: '["member"]',
      delete_roles: '["member"]'
    )
  end

  down do
    alter_table(:_schemas) do
      drop_column :read_roles
      drop_column :create_roles
      drop_column :update_roles
      drop_column :delete_roles
    end
  end
end
