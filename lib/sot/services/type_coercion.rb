require 'time'
require 'date'

module SOT
  class TypeCoercion
    class CoercionError < StandardError; end

    # Validate and coerce a single value for the given field type.
    # Returns the coerced value (always stored as a string-compatible JSON value).
    # Raises CoercionError if the value cannot be coerced.
    def self.coerce(value, type, field_name:)
      return value if value.nil?

      case type
      when 'string'
        coerce_string(value, field_name)
      when 'text'
        coerce_string(value, field_name)
      when 'integer'
        coerce_integer(value, field_name)
      when 'float'
        coerce_float(value, field_name)
      when 'boolean'
        coerce_boolean(value, field_name)
      when 'date'
        coerce_date(value, field_name)
      when 'datetime'
        coerce_datetime(value, field_name)
      when 'user'
        coerce_user(value, field_name)
      else
        value
      end
    end

    # Coerce a hash of field_name => value pairs, given a schema.
    # Only coerces fields present in the data hash.
    # Returns new hash with coerced values.
    def self.coerce_data(data, schema)
      return data unless data.is_a?(Hash)

      fields_by_name = schema.parsed_fields.each_with_object({}) { |f, h| h[f['name']] = f }
      coerced = {}

      data.each do |key, value|
        field_def = fields_by_name[key.to_s]
        if field_def && !value.nil?
          coerced[key] = coerce(value, field_def['type'], field_name: key.to_s)
        else
          coerced[key] = value
        end
      end

      coerced
    end

    class << self
      private

      def coerce_string(value, field_name)
        value.to_s
      end

      def coerce_integer(value, field_name)
        return value.to_s if value.is_a?(Integer)

        if value.is_a?(Float)
          raise CoercionError, "Field '#{field_name}': float value #{value} cannot be stored as integer (would lose precision)" unless value == value.floor
          return value.to_i.to_s
        end

        str = value.to_s.strip
        begin
          Integer(str, 10).to_s
        rescue ArgumentError, TypeError
          raise CoercionError, "Field '#{field_name}': cannot coerce #{value.inspect} to integer"
        end
      end

      def coerce_float(value, field_name)
        if value.is_a?(Numeric)
          Float(value).to_s
        else
          str = value.to_s.strip
          begin
            Float(str).to_s
          rescue ArgumentError, TypeError
            raise CoercionError, "Field '#{field_name}': cannot coerce #{value.inspect} to float"
          end
        end
      end

      def coerce_boolean(value, field_name)
        return value.to_s if value.is_a?(TrueClass) || value.is_a?(FalseClass)

        str = value.to_s.strip.downcase
        return 'true' if %w[true 1 yes].include?(str)
        return 'false' if %w[false 0 no].include?(str)

        raise CoercionError, "Field '#{field_name}': cannot coerce #{value.inspect} to boolean (accepted: true/false, 1/0, yes/no)"
      end

      def coerce_date(value, field_name)
        str = value.to_s.strip
        raise CoercionError, "Field '#{field_name}': date string is blank" if str.empty?

        # Accept YYYY-MM-DD format only for unambiguous dates
        unless str.match?(/\A\d{4}-\d{2}-\d{2}\z/)
          raise CoercionError, "Field '#{field_name}': date must be in YYYY-MM-DD format (got #{str.inspect})"
        end

        # Validate it's a real calendar date
        begin
          Date.parse(str)
        rescue Date::Error, ArgumentError => e
          raise CoercionError, "Field '#{field_name}': invalid date #{str.inspect} — #{e.message}"
        end

        str
      end

      def coerce_datetime(value, field_name)
        str = value.to_s.strip
        raise CoercionError, "Field '#{field_name}': datetime string is blank" if str.empty?

        # Step 1: Require unambiguous timezone info via regex.
        # Neither Time.parse nor DateTime.parse can reliably detect missing tz.
        # Accept: Z, +/-HH:MM, +/-HHMM, UTC, GMT.
        # Reject ambiguous abbreviations (EST, CET, PST, etc.).
        unless str.match?(/(?:Z|[+-]\d{2}:?\d{2}|\s(?:UTC|GMT))\s*$/i)
          raise CoercionError, "Field '#{field_name}': datetime must include timezone (e.g., Z, +02:00, UTC, GMT)"
        end

        # Step 2: Require a time component (not just a date).
        # Time.parse('2026-02-25Z') silently ignores the Z.
        # Require T or space before time digits to avoid matching timezone offsets like +02:00.
        unless str.match?(/[T ]\d{1,2}:\d{2}/)
          raise CoercionError, "Field '#{field_name}': datetime must include time component (e.g., 2026-02-25T15:00:00Z)"
        end

        # Step 3: Use DateTime.parse to catch invalid dates (Feb 30, etc.).
        # Time.parse silently overflows these.
        begin
          DateTime.parse(str)
        rescue Date::Error, ArgumentError => e
          raise CoercionError, "Field '#{field_name}': invalid datetime #{str.inspect} — #{e.message}"
        end

        # Step 4: Use Time.parse for the actual conversion.
        begin
          t = Time.parse(str)
        rescue ArgumentError => e
          raise CoercionError, "Field '#{field_name}': cannot parse datetime #{str.inspect} — #{e.message}"
        end

        # Step 5: Normalize to UTC ISO 8601.
        t.utc.iso8601
      end

      def coerce_user(value, field_name)
        str = value.to_s.strip
        raise CoercionError, "Field '#{field_name}': user value is blank" if str.empty?

        user = User.first(name: str)
        unless user
          available = User.select(:name).map(&:name).sort
          raise CoercionError, "Field '#{field_name}': user '#{str}' not found. Available users: #{available.join(', ')}"
        end

        str
      end
    end
  end
end
