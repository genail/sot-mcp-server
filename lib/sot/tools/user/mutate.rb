module SOT
  module Tools
    module User
      class Mutate < MCP::Tool
        tool_name 'sot_mutate'

        description <<~DESC
          Create, update, or delete a record. Supports atomic preconditions.

          Actions:
          - create: New record. Requires table and data. State defaults to first defined state for stateful tables.
          - update: Update existing record. Requires record_id and version.
            Data is MERGED into the existing record — only the fields you provide are changed.
            To remove a field, set it to null. To fully replace all data, set replace_data to true.
            To append text to an existing field value, use append_data instead of data.
            Only string and text fields support append. A field cannot appear in both data and append_data.
          - delete: Delete a record. Requires record_id and version.

          Version (required for update/delete):
            Pass the version number you received from sot_query. If the record has been modified
            since you last read it, the operation will be rejected — re-fetch and retry.
            Exception: version is NOT required for append-only updates (only append_data, no data/state).

          Preconditions (for update/delete):
            A hash of expected current values. The operation ONLY succeeds if ALL preconditions match.
            Example: { "state": "available" } — only proceed if current state is "available".

          IMPORTANT: Always use preconditions when changing state to avoid race conditions.
          NEVER guess record IDs. Use sot_query first to find the record.
        DESC

        input_schema(
          properties: {
            action: {
              type: 'string',
              enum: %w[create update delete],
              description: 'The mutation action'
            },
            table: {
              type: 'string',
              description: 'Table name (required for create)'
            },
            record_id: {
              type: 'integer',
              description: 'Record ID (required for update/delete)'
            },
            data: {
              type: 'object',
              description: 'Field values (required for create, optional for update)',
              additionalProperties: true
            },
            state: {
              type: 'string',
              description: 'State to set (optional)'
            },
            preconditions: {
              type: 'object',
              description: 'Expected current values for compare-and-swap (optional for update/delete)',
              additionalProperties: true
            },
            replace_data: {
              type: 'boolean',
              description: 'If true, data fully replaces existing data instead of merging (default false)'
            },
            append_data: {
              type: 'object',
              description: 'Key-value pairs to append to existing field values (string/text fields only)',
              additionalProperties: { type: 'string' }
            },
            version: {
              type: 'integer',
              description: 'Expected record version from sot_query (required for update/delete, except append-only updates)'
            }
          },
          required: ['action']
        )

        def self.call(server_context:, **params)
          user = server_context[:user]
          action = params[:action]

          case action
          when 'create' then handle_create(params, user)
          when 'update' then handle_update(params, user)
          when 'delete' then handle_delete(params, user)
          else
            error_response("Unknown action '#{action}'. Must be create, update, or delete.")
          end
        end

        private

        def self.handle_create(params, user)
          schema = SOT::SchemaService.resolve(params[:table])
          return error_response("Table '#{params[:table]}' not found.",
                                hint: 'Use sot_describe_tables to see available tables.') unless schema
          return error_response("'data' is required for create.", schema: schema) unless params[:data]

          record = SOT::MutationService.create(
            schema: schema,
            data: params[:data],
            state: params[:state],
            user: user
          )

          state_info = record.state ? " [#{record.state}]" : ''
          MCP::Tool::Response.new([{
            type: 'text',
            text: "Created record ##{record.id} (v#{record.current_version})#{state_info} in #{schema.full_name}:\n#{record.data}"
          }])
        rescue SOT::MutationService::ValidationError => e
          schema = SOT::SchemaService.resolve(params[:table])
          error_response(e.message, schema: schema)
        end

        def self.handle_update(params, user)
          return error_response("'record_id' is required for update.") unless params[:record_id]

          record = SOT::Record[params[:record_id]]
          return error_response("Record ##{params[:record_id]} not found.") unless record

          schema = record.schema
          result = SOT::MutationService.update(
            record: record,
            data: params[:data],
            state: params[:state],
            preconditions: params[:preconditions] || {},
            user: user,
            replace_data: params[:replace_data] || false,
            append_data: params[:append_data],
            expected_version: params[:version]
          )

          state_info = result.state ? " [#{result.state}]" : ''
          MCP::Tool::Response.new([{
            type: 'text',
            text: "Updated record ##{result.id} (v#{result.current_version})#{state_info} in #{schema.full_name}:\n#{result.data}"
          }])
        rescue SOT::MutationService::VersionConflict => e
          error_response(e.message, schema: e.record.schema, record: e.record)
        rescue SOT::MutationService::PreconditionFailed => e
          error_response(e.message, schema: e.record.schema, record: e.record)
        rescue SOT::MutationService::ValidationError => e
          record = SOT::Record[params[:record_id]]
          error_response(e.message, schema: record&.schema)
        end

        def self.handle_delete(params, user)
          return error_response("'record_id' is required for delete.") unless params[:record_id]

          record = SOT::Record[params[:record_id]]
          return error_response("Record ##{params[:record_id]} not found.") unless record

          schema = record.schema
          SOT::MutationService.delete(
            record: record,
            preconditions: params[:preconditions] || {},
            user: user,
            expected_version: params[:version]
          )

          MCP::Tool::Response.new([{
            type: 'text',
            text: "Deleted record ##{params[:record_id]} from #{schema.full_name}."
          }])
        rescue SOT::MutationService::VersionConflict => e
          error_response(e.message, schema: e.record.schema, record: e.record)
        rescue SOT::MutationService::PreconditionFailed => e
          error_response(e.message, schema: e.record.schema, record: e.record)
        rescue SOT::MutationService::ValidationError => e
          record = SOT::Record[params[:record_id]]
          error_response(e.message, schema: record&.schema)
        end

        def self.error_response(message, schema: nil, record: nil, hint: nil)
          text = SOT::ErrorFormatter.format(message, schema: schema, record: record, hint: hint)
          MCP::Tool::Response.new([{ type: 'text', text: text }], error: true)
        end
      end
    end
  end
end
