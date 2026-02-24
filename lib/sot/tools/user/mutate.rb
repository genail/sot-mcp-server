module SOT
  module Tools
    module User
      class Mutate < MCP::Tool
        tool_name 'sot_mutate'

        description <<~DESC
          Create, update, or delete a record. Supports atomic preconditions.

          Actions:
          - create: New record. Requires table and data. State defaults to first defined state for stateful tables.
          - update: Update existing record. Requires record_id. Provide data and/or state to change.
            Data is MERGED into the existing record — only the fields you provide are changed.
            To remove a field, set it to null. To fully replace all data, set replace_data to true.
          - delete: Delete a record. Requires record_id.

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
            text: "Created record ##{record.id}#{state_info} in #{schema.full_name}:\n#{record.data}"
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
            replace_data: params[:replace_data] || false
          )

          state_info = result.state ? " [#{result.state}]" : ''
          MCP::Tool::Response.new([{
            type: 'text',
            text: "Updated record ##{result.id}#{state_info} in #{schema.full_name}:\n#{result.data}"
          }])
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
            user: user
          )

          MCP::Tool::Response.new([{
            type: 'text',
            text: "Deleted record ##{params[:record_id]} from #{schema.full_name}."
          }])
        rescue SOT::MutationService::PreconditionFailed => e
          error_response(e.message, schema: e.record.schema, record: e.record)
        end

        def self.error_response(message, schema: nil, record: nil, hint: nil)
          text = SOT::ErrorFormatter.format(message, schema: schema, record: record, hint: hint)
          MCP::Tool::Response.new([{ type: 'text', text: text }], error: true)
        end
      end
    end
  end
end
