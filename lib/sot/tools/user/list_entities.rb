module SOT
  module Tools
    module User
      class ListEntities < MCP::Tool
        tool_name 'sot_list_entities'

        description <<~DESC
          List all entity types available in the Source of Truth.
          Returns each entity's namespace, name, description, fields (with types and descriptions), and valid states.

          USE THIS FIRST to understand what entity types exist before querying or mutating.

          Optional parameter: namespace — filter to a specific namespace (e.g., "org", "project").

          DO NOT guess entity type names. Always call this tool first to discover them.
        DESC

        input_schema(
          properties: {
            namespace: {
              type: 'string',
              description: 'Optional: filter by namespace (e.g., "org", "project")'
            }
          }
        )

        def self.call(server_context:, **params)
          schemas = SOT::SchemaService.list(namespace: params[:namespace])

          if schemas.empty?
            return MCP::Tool::Response.new([{
              type: 'text',
              text: "No entity types found.#{params[:namespace] ? ' Try without the namespace filter.' : ''}"
            }])
          end

          lines = schemas.map do |s|
            parts = ["## #{s.full_name}"]
            parts << "Description: #{s.description}" if s.description
            parts << "Fields:"
            s.parsed_fields.each do |f|
              req = f['required'] ? ' (required)' : ''
              desc = f['description'] ? " — #{f['description']}" : ''
              parts << "  - #{f['name']} (#{f['type']})#{req}#{desc}"
            end
            if s.stateful?
              parts << "States:"
              s.parsed_states.each do |st|
                desc = st['description'] ? " — #{st['description']}" : ''
                parts << "  - #{st['name']}#{desc}"
              end
            else
              parts << "Stateless"
            end
            parts.join("\n")
          end

          MCP::Tool::Response.new([{ type: 'text', text: lines.join("\n\n") }])
        end
      end
    end
  end
end
