module SOT
  module Tools
    module User
      class Read < MCP::Tool
        tool_name 'sot_read'

        description <<~DESC
          Read a specific field from a record, optionally slicing by character offset and limit.
          Use this after sot_query with snippet_fields to read more context around a match offset.

          Parameters:
          - record_id (required): The record ID to read from
          - field (required): The field name to read
          - offset: Character offset to start reading from (default 0)
          - limit: Number of characters to read (default: full field)
        DESC

        input_schema(
          properties: {
            record_id: { type: 'integer', description: 'The record ID to read from' },
            field: { type: 'string', description: 'The field name to read' },
            offset: { type: 'integer', minimum: 0, description: 'Character offset to start reading (default 0)' },
            limit: { type: 'integer', minimum: 0, description: 'Number of characters to read (default: full field)' }
          },
          required: %w[record_id field]
        )

        def self.call(server_context:, **params)
          user = server_context[:user]

          unless params[:record_id]
            return error_response("record_id is required.")
          end

          unless params[:field]
            return error_response("field is required.")
          end

          record = SOT::QueryService.find(params[:record_id])
          unless record
            return error_response("Record ##{params[:record_id]} not found.")
          end

          unless SOT::PermissionService.can?(user, record.schema, :read)
            return error_response("Record ##{params[:record_id]} not found.")
          end

          data = record.parsed_data
          field_name = params[:field]
          schema = record.schema

          unless schema.all_field_names.include?(field_name)
            return error_response("Field '#{field_name}' not found in table '#{schema.full_name}'.",
                                  schema: schema)
          end

          value = data[field_name]
          if value.nil?
            return MCP::Tool::Response.new([{
              type: 'text',
              text: "Record ##{record.id}, field '#{field_name}': (empty)"
            }])
          end

          value_str = value.to_s
          total_length = value_str.length
          char_offset = params[:offset] || 0
          char_limit = params[:limit]

          if char_offset < 0
            return error_response("offset must be non-negative.")
          end

          if char_limit && char_limit < 0
            return error_response("limit must be non-negative.")
          end

          if char_offset >= total_length
            return MCP::Tool::Response.new([{
              type: 'text',
              text: "Record ##{record.id}, field '#{field_name}' (#{total_length} chars total): offset #{char_offset} is beyond field length."
            }])
          end

          slice = if char_limit
                    value_str[char_offset, char_limit]
                  else
                    value_str[char_offset..]
                  end

          header = "Record ##{record.id}, field '#{field_name}'"
          if char_offset > 0 || char_limit
            header += " (offset #{char_offset}, showing #{slice.length} of #{total_length} chars)"
          else
            header += " (#{total_length} chars)"
          end

          MCP::Tool::Response.new([{
            type: 'text',
            text: "#{header}:\n#{slice}"
          }])
        end

        private

        def self.error_response(message, schema: nil)
          text = SOT::ErrorFormatter.format(message, schema: schema)
          MCP::Tool::Response.new([{ type: 'text', text: text }], error: true)
        end
      end
    end
  end
end
