Sequel.migration do
  change do
    create_table(:_users) do
      primary_key :id
      String :name, null: false, unique: true
      String :token_hash, null: false
      TrueClass :is_admin, default: false
      DateTime :created_at, null: false
      DateTime :updated_at, null: false
    end
  end
end
