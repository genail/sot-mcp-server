Sequel.migration do
  change do
    create_table(:_activity_log) do
      primary_key :id
      foreign_key :user_id, :_users, null: false
      Integer :record_id
      foreign_key :schema_id, :_schemas, null: false
      String :action, null: false
      String :changes, text: true, null: false
      DateTime :created_at, null: false

      index [:record_id]
      index [:schema_id]
      index [:user_id]
      index [:created_at]
    end
  end
end
