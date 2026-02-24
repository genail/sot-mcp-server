Sequel.migration do
  change do
    add_column :_users, :is_active, TrueClass, default: true, null: false
  end
end
