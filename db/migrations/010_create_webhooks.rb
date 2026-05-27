Sequel.migration do
  change do
    create_table(:_webhooks) do
      primary_key :id
      String :name, null: false, unique: true
      String :description, text: true
      String :url, null: false
      String :http_method, null: false, default: 'POST'
      String :headers, text: true
      String :payload_template, text: true, null: false
      String :variables, text: true, null: false, default: '[]'
      String :allowed_roles, text: true
      DateTime :created_at, null: false
      DateTime :updated_at, null: false
    end

    create_table(:_webhook_logs) do
      primary_key :id
      foreign_key :webhook_id, :_webhooks, null: false, on_delete: :cascade
      foreign_key :user_id, :_users, null: false
      String :variable_values, text: true
      Integer :status_code
      String :response_body, text: true
      TrueClass :success, null: false
      String :error_message, text: true
      DateTime :created_at, null: false
    end
  end
end
