module SOT
  module Tools
    module Admin
      class ViewFeedback < MCP::Tool
        tool_name 'sot_admin_view_feedback'

        description <<~DESC
          View and manage feedback submitted by agents about confusing descriptions.

          Actions:
          - list: View feedback entries (optionally filtered by table or resolved status).
          - resolve: Mark a feedback entry as resolved.
        DESC

        input_schema(
          properties: {
            action: {
              type: 'string',
              enum: %w[list resolve],
              description: 'The action (default: list)'
            },
            table: { type: 'string', description: 'Filter by table (for list)' },
            resolved: { type: 'boolean', description: 'Filter by resolved status (for list)' },
            feedback_id: { type: 'integer', description: 'Feedback ID to resolve (for resolve action)' },
            limit: { type: 'integer', description: 'Max results (default 50)' }
          }
        )

        def self.call(server_context:, **params)
          action = params[:action] || 'list'

          case action
          when 'list' then handle_list(params)
          when 'resolve' then handle_resolve(params)
          else
            MCP::Tool::Response.new([{ type: 'text', text: "Unknown action '#{action}'." }], error: true)
          end
        end

        private

        def self.handle_list(params)
          dataset = SOT::Feedback.order(Sequel.desc(:created_at))

          if params[:table]
            schema = SOT::SchemaService.resolve(params[:table])
            dataset = dataset.where(schema_id: schema.id) if schema
          end

          dataset = dataset.where(resolved: params[:resolved]) if params.key?(:resolved)
          entries = dataset.limit(params[:limit] || 50).all

          if entries.empty?
            return MCP::Tool::Response.new([{ type: 'text', text: 'No feedback entries found.' }])
          end

          lines = entries.map do |f|
            user = SOT::User[f.user_id]
            schema = f.schema_id ? SOT::Schema[f.schema_id] : nil
            status = f.resolved ? '[RESOLVED]' : '[OPEN]'
            entity_info = schema ? " (#{schema.full_name})" : ''

            parts = ["##{f.id} #{status}#{entity_info} by #{user&.name || 'unknown'} at #{f.created_at}"]
            parts << "  Context: #{f.context}"
            parts << "  Confusion: #{f.confusion}"
            parts << "  Suggestion: #{f.suggestion}" if f.suggestion
            parts.join("\n")
          end

          MCP::Tool::Response.new([{
            type: 'text',
            text: "Feedback (#{entries.length} entries):\n\n#{lines.join("\n\n")}"
          }])
        end

        def self.handle_resolve(params)
          return MCP::Tool::Response.new([{ type: 'text', text: "'feedback_id' is required." }], error: true) unless params[:feedback_id]

          feedback = SOT::Feedback[params[:feedback_id]]
          return MCP::Tool::Response.new([{ type: 'text', text: "Feedback ##{params[:feedback_id]} not found." }], error: true) unless feedback

          feedback.update(resolved: true)
          MCP::Tool::Response.new([{ type: 'text', text: "Feedback ##{feedback.id} marked as resolved." }])
        end
      end
    end
  end
end
