Sequel.migration do
  change do
    add_column :_records, :version, Integer, default: 1, null: false
  end
end
