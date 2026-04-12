module SOT
  module Tools
    module User
      class DescribeTables < MCP::Tool
        tool_name 'sot_describe_tables'

        description <<~DESC
          Describe tables available in the Source of Truth.

          By default, returns a lightweight summary: each table's name and description only.
          To get full field and state details, either:
          - Pass specific table names in `tables` to describe only those (recommended).
          - Set `detail: true` to describe ALL tables in full (can be heavy with many tables).

          USE THIS FIRST to understand what tables exist before querying or mutating.

          DO NOT guess table names. Always call this tool first to discover them.
        DESC

        input_schema(
          properties: {
            namespace: {
              type: 'string',
              description: 'Filter by namespace (e.g., "org", "project")'
            },
            tables: {
              type: 'array',
              items: { type: 'string' },
              description: 'Table names to describe in full detail (e.g., ["org.locks", "org.docs"])'
            },
            detail: {
              type: 'boolean',
              description: 'If true, show full field/state details for ALL tables (can be heavy). Prefer using `tables` to select specific ones.'
            }
          }
        )

        def self.call(server_context:, **params)
          user = server_context[:user]

          if params[:tables] && !params[:tables].empty?
            return describe_selected(params[:tables], user)
          end

          all_schemas = SOT::SchemaService.list(namespace: params[:namespace])
          schemas = all_schemas.select { |s| SOT::PermissionService.can?(user, s, :read) }

          if schemas.empty?
            return MCP::Tool::Response.new([{
              type: 'text',
              text: "No tables found.#{params[:namespace] ? ' Try without the namespace filter.' : ''}"
            }])
          end

          if params[:detail]
            lines = schemas.map { |s| format_detailed(s) }
          else
            lines = schemas.map { |s| format_summary(s) }
          end

          MCP::Tool::Response.new([{ type: 'text', text: lines.join("\n\n") }])
        end

        private

        def self.describe_selected(table_names, user)
          lines = []
          not_found = []

          table_names.each do |name|
            schema = SOT::SchemaService.resolve(name)
            if schema && SOT::PermissionService.can?(user, schema, :read)
              lines << format_detailed(schema)
            else
              not_found << name
            end
          end

          parts = []
          parts << lines.join("\n\n") unless lines.empty?
          unless not_found.empty?
            parts << "Tables not found: #{not_found.join(', ')}. Use sot_describe_tables to see available tables."
          end

          MCP::Tool::Response.new([{ type: 'text', text: parts.join("\n\n") }])
        end

        def self.format_summary(schema)
          desc = schema.description ? " — #{schema.description}" : ''
          stateful = schema.stateful? ? ' (stateful)' : ''
          "- #{schema.full_name}#{stateful}#{desc}"
        end

        def self.format_detailed(schema)
          parts = ["## #{schema.full_name}"]
          parts << "Description: #{schema.description}" if schema.description
          parts << "Fields:"
          schema.parsed_fields.each do |f|
            req = f['required'] ? ' (required)' : ''
            desc = f['description'] ? " — #{f['description']}" : ''
            parts << "  - #{f['name']} (#{f['type']})#{req}#{desc}"
          end
          if schema.stateful?
            parts << "States:"
            schema.parsed_states.each do |st|
              desc = st['description'] ? " — #{st['description']}" : ''
              parts << "  - #{st['name']}#{desc}"
            end
          else
            parts << "Stateless"
          end
          parts.join("\n")
        end
      end
    end
  end
end
