module SOT
  module Tools
    module User
      class Query < MCP::Tool
        tool_name 'sot_query'

        description <<~DESC
          Query records from one or more tables, or fetch a single record by ID.
          Use sot_describe_tables first to discover available tables and their field names.

          Parameters:
          - table (required): Table name or array of table names, e.g., "org.locks" or ["org.locks", "org.docs"]. When multiple tables are specified, filters and state must be valid for all of them.
          - record_id: Fetch a specific record by ID (returns one record, ignores filters/pagination)
          - filters: Hash of field_name => value for exact match filtering
          - search: Text search across record data. Use 3+ specific terms for best results (e.g., "deployment staging migration" not just "deployment"). Results ranked by relevance — records matching more terms appear first. Case-insensitive.
          - state: Filter by current state
          - limit: Max records to return (default 100)
          - offset: Pagination offset (default 0)

          DO NOT use field names not defined in the schema. Call sot_describe_tables first.
        DESC

        input_schema(
          properties: {
            table: {
              oneOf: [
                { type: 'string' },
                { type: 'array', items: { type: 'string' }, minItems: 1 }
              ],
              description: 'Table name or array of table names, e.g. "org.locks" or ["org.locks", "org.docs"]'
            },
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
              description: 'Text search across record data. Use 3+ specific terms for best results. Results ranked by relevance (most matching terms first). Case-insensitive.'
            },
            full_fields: {
              type: 'array', items: { type: 'string' },
              description: 'Fields to return in full (e.g. title, tags, status). Recommended for short fields. Use sot_describe_tables to see field names.'
            },
            snippet_fields: {
              type: 'array', items: { type: 'string' },
              description: 'Fields to return as match snippets only (requires search). Each snippet shows surrounding context around the match with its character offset. Use sot_read to read more around an offset. Recommended for long content fields. Up to 3 snippets per field.'
            },
            snippet_context: {
              type: 'integer',
              description: 'Characters of context before/after each match in snippet_fields (default 100)'
            },
            state: { type: 'string', description: 'Filter by state' },
            limit: { type: 'integer', description: 'Max results (default 100)' },
            offset: { type: 'integer', description: 'Pagination offset (default 0)' }
          },
          required: ['table']
        )

        def self.call(server_context:, **params)
          user = server_context[:user]
          table_names = Array(params[:table]).uniq

          # Resolve all tables
          resolved = SOT::SchemaService.resolve_many(table_names)
          not_found = resolved.select { |_, v| v.nil? }.keys
          # Also treat inaccessible tables as "not found"
          resolved.each do |name, schema|
            next unless schema
            unless SOT::PermissionService.can?(user, schema, :read)
              not_found << name
              resolved[name] = nil
            end
          end
          unless not_found.empty?
            return error_response(
              "Table(s) not found: #{not_found.join(', ')}.",
              hint: 'Use sot_describe_tables to see available tables.'
            )
          end
          schemas = resolved.values

          # Single record lookup by ID
          if params[:record_id]
            record = SOT::QueryService.find(params[:record_id])
            unless record
              return error_response("Record ##{params[:record_id]} not found.")
            end
            unless SOT::PermissionService.can?(user, record.schema, :read)
              return error_response("Record ##{params[:record_id]} not found.")
            end
            table_name = record.schema.full_name
            state_info = record.state ? " [#{record.state}]" : ''
            return MCP::Tool::Response.new([{
              type: 'text',
              text: "Record ##{record.id} (v#{record.current_version})#{state_info} in #{table_name}: #{record.data}"
            }])
          end

          # Validate filters against ALL schemas
          filters = params[:filters] || {}
          unless filters.empty?
            schemas.each do |s|
              unknown = filters.keys.map(&:to_s) - s.all_field_names
              unless unknown.empty?
                return error_response(
                  "Filter field(s) #{unknown.join(', ')} not found in table '#{s.full_name}'.",
                  schema: s
                )
              end
            end
          end

          # Validate state filter against ALL schemas
          if params[:state]
            schemas.each do |s|
              unless s.stateful?
                return error_response(
                  "Cannot filter by state: table '#{s.full_name}' is stateless.",
                  schema: s
                )
              end
              unless s.valid_state?(params[:state])
                return error_response(
                  "State '#{params[:state]}' is not valid for table '#{s.full_name}'.",
                  schema: s
                )
              end
            end
          end

          # Validate full_fields / snippet_fields
          full_fields = params[:full_fields]
          snippet_fields = params[:snippet_fields]
          snippet_context = params[:snippet_context] || 100

          if snippet_fields && !params[:search]
            return error_response("snippet_fields requires a search term. Use full_fields for queries without search.")
          end

          if full_fields && snippet_fields
            overlap = full_fields & snippet_fields
            unless overlap.empty?
              return error_response("Field(s) #{overlap.join(', ')} cannot be in both full_fields and snippet_fields.")
            end
          end

          all_field_params = (Array(full_fields) + Array(snippet_fields)).uniq
          unless all_field_params.empty?
            schemas.each do |s|
              unknown = all_field_params - s.all_field_names
              unless unknown.empty?
                return error_response(
                  "Field(s) #{unknown.join(', ')} not found in table '#{s.full_name}'.",
                  schema: s
                )
              end
            end
          end

          schema_lookup = schemas.each_with_object({}) { |s, h| h[s.id] = s.full_name }
          schema_ids = schemas.map(&:id)
          search = params[:search]
          limit = params[:limit] || 100
          offset = params[:offset] || 0

          records = SOT::QueryService.list(
            schema_ids,
            filters: filters,
            search: search,
            state: params[:state],
            limit: limit,
            offset: offset
          )

          if records.empty?
            table_label = schemas.map(&:full_name).join(', ')
            return MCP::Tool::Response.new([{
              type: 'text',
              text: "No records found for #{table_label} with the given filters."
            }])
          end

          use_field_mode = full_fields || snippet_fields
          search_terms = search ? SOT::QueryService.normalize_search(search) : []
          multi_table = schemas.length > 1

          lines = records.map do |r|
            state_info = r.state ? " [#{r.state}]" : ''
            table_prefix = multi_table ? " in #{schema_lookup[r.schema_id]}" : ''

            if use_field_mode
              format_record_with_fields(r, state_info, table_prefix,
                                        full_fields: full_fields || [],
                                        snippet_fields: snippet_fields || [],
                                        search_terms: search_terms,
                                        snippet_context: snippet_context)
            else
              "Record ##{r.id} (v#{r.current_version})#{state_info}#{table_prefix}: #{r.data}"
            end
          end

          count = SOT::QueryService.count(schema_ids, filters: filters, search: search, state: params[:state])
          from = offset + 1
          to = offset + records.length
          table_label = schemas.map(&:full_name).join(', ')
          header = "Showing #{from}-#{to} of #{count} record(s) for #{table_label}:"

          MCP::Tool::Response.new([{
            type: 'text',
            text: "#{header}\n\n#{lines.join("\n")}"
          }])
        end

        private

        def self.format_record_with_fields(record, state_info, table_prefix,
                                            full_fields:, snippet_fields:,
                                            search_terms:, snippet_context:)
          data = record.parsed_data
          parts = ["Record ##{record.id} (v#{record.current_version})#{state_info}#{table_prefix}:"]

          full_fields.each do |field|
            value = data[field]
            parts << "  #{field}: #{value}" unless value.nil?
          end

          if snippet_fields.any? && search_terms.any?
            snippets = SOT::SnippetService.extract(
              data, search_terms, fields: snippet_fields, context: snippet_context
            )

            snippet_fields.each do |field|
              matches = snippets[field] || []
              if matches.empty?
                parts << "  #{field}: (no match)"
              else
                matches.each do |m|
                  terms_label = m[:terms] ? m[:terms].join(', ') : m[:term]
                  parts << "  #{field} [match at offset #{m[:offset]}, terms: #{terms_label}]: ...#{m[:snippet]}..."
                end
              end
            end
          end

          parts.join("\n")
        end

        def self.error_response(message, schema: nil, hint: nil)
          text = SOT::ErrorFormatter.format(message, schema: schema, hint: hint)
          MCP::Tool::Response.new([{ type: 'text', text: text }], error: true)
        end
      end
    end
  end
end
