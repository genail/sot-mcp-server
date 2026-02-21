Sequel.migration do
  change do
    create_table(:_records) do
      primary_key :id
      foreign_key :schema_id, :_schemas, null: false, on_delete: :cascade
      String :data, text: true, null: false, default: '{}'
      String :state
      foreign_key :created_by, :_users, null: false
      foreign_key :updated_by, :_users, null: false
      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      index [:schema_id]
      index [:schema_id, :state]
    end
  end
end
