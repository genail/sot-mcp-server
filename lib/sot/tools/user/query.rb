module SOT
  module Tools
    module User
      class Query < MCP::Tool
        tool_name 'sot_query'

        description <<~DESC
          Query records of a specific table, or fetch a single record by ID.
          Use sot_describe_tables first to discover available tables and their field names.

          Parameters:
          - table (required): The table name, e.g., "org.locks" or just "locks"
          - record_id: Fetch a specific record by ID (returns one record, ignores filters/pagination)
          - filters: Hash of field_name => value for exact match filtering
          - search: Text search across record data. String or array of strings. All terms must match (AND logic, case-insensitive).
          - state: Filter by current state
          - limit: Max records to return (default 100)
          - offset: Pagination offset (default 0)

          DO NOT use field names not defined in the schema. Call sot_describe_tables first.
        DESC

        input_schema(
          properties: {
            table: { type: 'string', description: 'Table name, e.g. "org.locks"' },
            record_id: { type: 'integer', description: 'Fetch a single record by ID' },
            filters: {
              type: 'object',
              description: 'Key-value pairs to filter by (exact match on data fields)',
              additionalProperties: { type: 'string' }
            },
            search: {
              oneOf: [
                { type: 'string' },
                { type: 'array', items: { type: 'string' } }
              ],
              description: 'Text search across record data. String or array of strings — all must match (AND, case-insensitive).'
            },
            state: { type: 'string', description: 'Filter by state' },
            limit: { type: 'integer', description: 'Max results (default 100)' },
            offset: { type: 'integer', description: 'Pagination offset (default 0)' }
          },
          required: ['table']
        )

        def self.call(server_context:, **params)
          schema = SOT::SchemaService.resolve(params[:table])
          unless schema
            return error_response("Table '#{params[:table]}' not found.",
                                  hint: 'Use sot_describe_tables to see available tables.')
          end

          # Single record lookup by ID
          if params[:record_id]
            record = SOT::QueryService.find(schema, params[:record_id])
            unless record
              return error_response("Record ##{params[:record_id]} not found in #{schema.full_name}.")
            end
            state_info = record.state ? " [#{record.state}]" : ''
            return MCP::Tool::Response.new([{
              type: 'text',
              text: "Record ##{record.id} (v#{record.current_version})#{state_info}: #{record.data}"
            }])
          end

          filters = params[:filters] || {}
          unknown = filters.keys.map(&:to_s) - schema.all_field_names
          unless unknown.empty?
            return error_response("Unknown filter fields: #{unknown.join(', ')}", schema: schema)
          end

          search = Array(params[:search]).compact

          records = SOT::QueryService.list(
            schema,
            filters: filters,
            search: search,
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
            "Record ##{r.id} (v#{r.current_version})#{state_info}: #{r.data}"
          end

          count = SOT::QueryService.count(schema, filters: filters, search: search, state: params[:state])
          limit = params[:limit] || 100
          offset = params[:offset] || 0
          from = offset + 1
          to = offset + records.length
          header = "Showing #{from}-#{to} of #{count} record(s) for #{schema.full_name}:"

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
