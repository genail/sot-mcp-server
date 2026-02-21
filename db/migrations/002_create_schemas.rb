Sequel.migration do
  change do
    create_table(:_schemas) do
      primary_key :id
      String :namespace, null: false
      String :name, null: false
      String :description, text: true
      String :fields, text: true, null: false
      String :states, text: true
      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      unique [:namespace, :name]
    end
  end
end
