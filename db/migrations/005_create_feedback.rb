Sequel.migration do
  change do
    create_table(:_feedback) do
      primary_key :id
      foreign_key :user_id, :_users, null: false
      foreign_key :schema_id, :_schemas, on_delete: :set_null
      String :context, text: true, null: false
      String :confusion, text: true, null: false
      String :suggestion, text: true
      TrueClass :resolved, default: false
      DateTime :created_at, null: false
    end
  end
end
