module SOT
  module Tools
    module User
      class FeedbackTool < MCP::Tool
        tool_name 'sot_feedback'

        description <<~DESC
          Report confusing, contradictory, or unclear table/field/state descriptions.
          Use this when you encounter descriptions that don't make sense, are ambiguous, or seem wrong.
          A human admin will review your feedback and improve the descriptions.

          Provide:
          - context: What you were trying to do
          - confusion: What was confusing or contradictory
          - table (optional): Which table this is about
          - suggestion (optional): Your suggested improvement
        DESC

        input_schema(
          properties: {
            table: { type: 'string', description: 'The table this feedback is about (optional)' },
            context: { type: 'string', description: 'What you were trying to do' },
            confusion: { type: 'string', description: 'What was confusing or contradictory' },
            suggestion: { type: 'string', description: 'Your suggested improvement (optional)' }
          },
          required: %w[context confusion]
        )

        def self.call(server_context:, **params)
          user = server_context[:user]
          schema = params[:table] ? SOT::SchemaService.resolve(params[:table]) : nil

          feedback = SOT::Feedback.create(
            user_id: user.id,
            schema_id: schema&.id,
            context: params[:context],
            confusion: params[:confusion],
            suggestion: params[:suggestion]
          )

          MCP::Tool::Response.new([{
            type: 'text',
            text: "Feedback recorded (ID: #{feedback.id}). An admin will review it. Thank you for helping improve the descriptions."
          }])
        end
      end
    end
  end
end
