module SOT
  module Tools
    module User
      class ActivityLogTool < MCP::Tool
        tool_name 'sot_activity_log'

        description <<~DESC
          View the change history for records.
          Shows who changed what, when, and the before/after diff.

          Filter by table, specific record ID, user name, or action type.
        DESC

        input_schema(
          properties: {
            table: { type: 'string', description: 'Filter by table (e.g., "org.locks")' },
            record_id: { type: 'integer', description: 'Filter by specific record ID' },
            user_name: { type: 'string', description: 'Filter by user name' },
            action: {
              type: 'string',
              enum: %w[create update delete],
              description: 'Filter by action type'
            },
            limit: { type: 'integer', description: 'Max results (default 50)' }
          },
        )

        def self.call(server_context:, **params)
          dataset = SOT::ActivityLog.order(Sequel.desc(:created_at))

          if params[:table]
            schema = SOT::SchemaService.resolve(params[:table])
            unless schema
              text = SOT::ErrorFormatter.format(
                "Table '#{params[:table]}' not found.",
                hint: 'Use sot_list_tables to see available tables.'
              )
              return MCP::Tool::Response.new([{ type: 'text', text: text }], error: true)
            end
            dataset = dataset.where(schema_id: schema.id)
          end

          if params[:record_id]
            dataset = dataset.where(record_id: params[:record_id])
          end

          if params[:user_name]
            user = SOT::User.first(name: params[:user_name])
            if user
              dataset = dataset.where(user_id: user.id)
            else
              return MCP::Tool::Response.new([{
                type: 'text',
                text: "No activity found (user '#{params[:user_name]}' not found)."
              }])
            end
          end

          dataset = dataset.where(action: params[:action]) if params[:action]
          entries = dataset.limit(params[:limit] || 50).all

          if entries.empty?
            return MCP::Tool::Response.new([{
              type: 'text',
              text: 'No activity log entries found with the given filters.'
            }])
          end

          lines = entries.map do |e|
            user = SOT::User[e.user_id]
            schema = SOT::Schema[e.schema_id]
            user_name = user&.name || 'unknown'
            entity_name = schema&.full_name || 'unknown'
            record_ref = e.record_id ? " record ##{e.record_id}" : ' (deleted record)'

            "#{e.created_at} | #{user_name} | #{e.action} | #{entity_name}#{record_ref}\n  Changes: #{e.changes}"
          end

          MCP::Tool::Response.new([{
            type: 'text',
            text: "Activity log (#{entries.length} entries):\n\n#{lines.join("\n\n")}"
          }])
        end
      end
    end
  end
end
