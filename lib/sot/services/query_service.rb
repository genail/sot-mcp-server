module SOT
  class QueryService
    STOPWORDS = %w[
      a an the and or but in on at to of is it as be by do go so up if no
      we he she my your its our was are for not this that from with have had
      has will would can could should may than then when who which how what where
    ].to_set.freeze

    def self.list(schema, filters: {}, state: nil, search: [], limit: 100, offset: 0)
      terms = normalize_search(search)
      dataset = build_dataset(schema, filters: filters, state: state, search_terms: terms)

      if terms.empty?
        dataset.order(:id).limit(limit).offset(offset).all
      else
        relevance = terms.map { |t| Sequel.case([[Sequel.ilike(:data, "%#{t}%"), 1]], 0) }
        relevance_sum = relevance.reduce { |sum, expr| sum + expr }

        dataset
          .select_append(relevance_sum.as(:relevance))
          .order(Sequel.desc(:relevance), :id)
          .limit(limit).offset(offset).all
      end
    end

    def self.count(schema, filters: {}, state: nil, search: [])
      terms = normalize_search(search)
      dataset = build_dataset(schema, filters: filters, state: state, search_terms: terms)
      dataset.count
    end

    def self.find(schema, record_id)
      Record.first(id: record_id, schema_id: schema.id)
    end

    # Normalize raw search input into individual terms.
    # Splits all inputs on whitespace, removes stopwords, deduplicates.
    def self.normalize_search(raw)
      Array(raw).compact
        .flat_map { |s| s.to_s.split }
        .map { |t| t.strip.downcase }
        .reject { |t| t.empty? || STOPWORDS.include?(t) }
        .uniq
    end

    private

    def self.build_dataset(schema, filters: {}, state: nil, search_terms: [])
      dataset = Record.where(schema_id: schema.id)

      dataset = dataset.where(state: state) if state

      filters.each do |field_name, value|
        dataset = dataset.where(
          Sequel.lit("json_extract(data, ?) = ?", "$.#{field_name}", value)
        )
      end

      if search_terms.any?
        or_conditions = search_terms.map { |t| Sequel.ilike(:data, "%#{t}%") }
        dataset = dataset.where(Sequel.|(*or_conditions))
      end

      dataset
    end
  end
end
