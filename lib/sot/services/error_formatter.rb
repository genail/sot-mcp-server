module SOT
  class ErrorFormatter
    FEEDBACK_TIP = "Tip: If you find these descriptions confusing or contradictory, use sot_feedback to report it so the admin can improve them."

    def self.format(message, schema: nil, record: nil, hint: nil)
      parts = ["ERROR: #{message}"]

      if schema
        parts << ""
        parts << "--- Schema Context: #{schema.full_name} ---"
        parts << "Description: #{schema.description}" if schema.description

        parts << "Fields:"
        schema.parsed_fields.each do |f|
          req = f['required'] ? ' (required)' : ''
          desc = f['description'] ? ": #{f['description']}" : ''
          parts << "  - #{f['name']} (#{f['type']})#{req}#{desc}"
        end

        if schema.stateful?
          parts << "Valid states:"
          schema.parsed_states.each do |s|
            desc = s['description'] ? ": #{s['description']}" : ''
            parts << "  - #{s['name']}#{desc}"
          end
        end
      end

      if record
        parts << ""
        parts << "Current record state: #{record.state || 'N/A'}"
        parts << "Current data: #{record.data}"
      end

      parts << ""
      parts << "Hint: #{hint}" if hint
      parts << FEEDBACK_TIP

      parts.join("\n")
    end
  end
end
