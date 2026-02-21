module SOT
  class QueryService
    def self.list(schema, filters: {}, state: nil, limit: 100, offset: 0)
      dataset = Record.where(schema_id: schema.id)

      dataset = dataset.where(state: state) if state

      filters.each do |field_name, value|
        dataset = dataset.where(
          Sequel.lit("json_extract(data, ?) = ?", "$.#{field_name}", value)
        )
      end

      dataset.order(:id).limit(limit).offset(offset).all
    end

    def self.count(schema, filters: {}, state: nil)
      dataset = Record.where(schema_id: schema.id)
      dataset = dataset.where(state: state) if state

      filters.each do |field_name, value|
        dataset = dataset.where(
          Sequel.lit("json_extract(data, ?) = ?", "$.#{field_name}", value)
        )
      end

      dataset.count
    end

    def self.find(schema, record_id)
      Record.first(id: record_id, schema_id: schema.id)
    end
  end
end
