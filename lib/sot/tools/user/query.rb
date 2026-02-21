module SOT
  module Tools
    module User
      class Query < MCP::Tool
        tool_name 'sot_query'

        description <<~DESC
          Query records of a specific entity type.
          Use sot_list_entities first to discover available entity types and their field names.

          Parameters:
          - entity (required): The entity type name, e.g., "org.locks" or just "locks"
          - filters: Hash of field_name => value for exact match filtering
          - state: Filter by current state
          - limit: Max records to return (default 100)
          - offset: Pagination offset (default 0)

          DO NOT use field names not defined in the schema. Call sot_list_entities first.
        DESC

        input_schema(
          properties: {
            entity: { type: 'string', description: 'Entity type name, e.g. "org.locks"' },
            filters: {
              type: 'object',
              description: 'Key-value pairs to filter by (exact match on data fields)',
              additionalProperties: { type: 'string' }
            },
            state: { type: 'string', description: 'Filter by state' },
            limit: { type: 'integer', description: 'Max results (default 100)' },
            offset: { type: 'integer', description: 'Pagination offset (default 0)' }
          },
          required: ['entity']
        )

        def self.call(server_context:, **params)
          schema = SOT::SchemaService.resolve(params[:entity])
          unless schema
            return error_response("Entity type '#{params[:entity]}' not found.",
                                  hint: 'Use sot_list_entities to see available entity types.')
          end

          filters = params[:filters] || {}
          unknown = filters.keys.map(&:to_s) - schema.all_field_names
          unless unknown.empty?
            return error_response("Unknown filter fields: #{unknown.join(', ')}", schema: schema)
          end

          records = SOT::QueryService.list(
            schema,
            filters: filters,
            state: params[:state],
            limit: params[:limit] || 100,
            offset: params[:offset] || 0
          )

          if records.empty?
            return MCP::Tool::Response.new([{
              type: 'text',
              text: "No records found for #{schema.full_name} with the given filters."
            }])
          end

          lines = records.map do |r|
            state_info = r.state ? " [#{r.state}]" : ''
            "Record ##{r.id}#{state_info}: #{r.data}"
          end

          count = SOT::QueryService.count(schema, filters: filters, state: params[:state])
          header = "Found #{count} record(s) for #{schema.full_name}:"

          MCP::Tool::Response.new([{
            type: 'text',
            text: "#{header}\n\n#{lines.join("\n")}"
          }])
        end

        private

        def self.error_response(message, schema: nil, hint: nil)
          text = SOT::ErrorFormatter.format(message, schema: schema, hint: hint)
          MCP::Tool::Response.new([{ type: 'text', text: text }], error: true)
        end
      end
    end
  end
end
