module SOT
  class QueryService
    def self.list(schema, filters: {}, state: nil, search: [], limit: 100, offset: 0)
      dataset = build_dataset(schema, filters: filters, state: state, search: search)
      dataset.order(:id).limit(limit).offset(offset).all
    end

    def self.count(schema, filters: {}, state: nil, search: [])
      dataset = build_dataset(schema, filters: filters, state: state, search: search)
      dataset.count
    end

    def self.find(schema, record_id)
      Record.first(id: record_id, schema_id: schema.id)
    end

    private

    def self.build_dataset(schema, filters: {}, state: nil, search: [])
      dataset = Record.where(schema_id: schema.id)

      dataset = dataset.where(state: state) if state

      filters.each do |field_name, value|
        dataset = dataset.where(
          Sequel.lit("json_extract(data, ?) = ?", "$.#{field_name}", value)
        )
      end

      search.each do |term|
        dataset = dataset.where(Sequel.ilike(:data, "%#{term}%"))
      end

      dataset
    end
  end
end
