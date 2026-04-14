require 'json'
require 'logger'

# Transport-layer type coercion shim for MCP tool calls.
#
# Workaround for a Claude Code MCP client serialization bug: integer, boolean,
# and object arguments arrive over the wire as JSON strings (e.g. "16" instead
# of 16). The server's strict schema validator rejects them. We coerce at the
# transport boundary so tool schemas and MutationService can stay strict.
#
# Scope is narrow on purpose: top-level keys of params.arguments only, and only
# when the tool's input_schema declares the target type. Remove this shim once
# the upstream Claude Code bug is fixed.
module SOT
  module Middleware
    class McpTypeCoercer
      INTEGER_RE = /\A-?\d+\z/.freeze
      NUMBER_RE  = /\A-?\d+(\.\d+)?\z/.freeze

      def self.logger
        @logger ||= Logger.new($stderr)
      end

      # Reads the Rack request body, coerces tool-call arguments in place if
      # applicable, rewrites rack.input, and returns. Swallows any parse error
      # so malformed bodies fall through to the transport unchanged.
      def self.preprocess!(env, tools_by_name)
        return unless env['REQUEST_METHOD'] == 'POST'

        input = env['rack.input']
        return unless input

        raw = input.read
        input.rewind if input.respond_to?(:rewind)
        return if raw.nil? || raw.empty?

        begin
          payload = JSON.parse(raw)
        rescue JSON::ParserError
          rewrite_body(env, raw)
          return
        end

        changed = coerce_payload!(payload, tools_by_name)

        rewrite_body(env, changed ? JSON.generate(payload) : raw)
      end

      def self.coerce_payload!(payload, tools_by_name)
        return false unless payload.is_a?(Hash)
        return false unless payload['method'] == 'tools/call'
        return false unless payload.key?('id') # skip notifications

        params = payload['params']
        return false unless params.is_a?(Hash)

        tool_name = params['name']
        arguments = params['arguments']
        return false unless tool_name.is_a?(String) && arguments.is_a?(Hash)

        tool = tools_by_name[tool_name]
        return false unless tool

        properties = schema_properties(tool)
        return false unless properties.is_a?(Hash) && !properties.empty?

        changed = false
        arguments.each do |key, value|
          prop = properties[key.to_sym] || properties[key.to_s]
          next unless prop.is_a?(Hash)

          declared_type = prop[:type] || prop['type']
          next unless declared_type.is_a?(String) # skip union/missing types

          coerced, did_change = coerce_value(value, declared_type)
          next unless did_change

          arguments[key] = coerced
          changed = true
          logger.warn(
            "Coerced #{tool_name}.#{key} from #{value.class} to #{declared_type} " \
            '(Claude Code MCP client bug workaround)'
          )
        end

        changed
      end

      def self.coerce_value(value, declared_type)
        case declared_type
        when 'integer'
          if value.is_a?(String) && value =~ INTEGER_RE
            [Integer(value, 10), true]
          else
            [value, false]
          end
        when 'number'
          if value.is_a?(String) && value =~ NUMBER_RE
            [Float(value), true]
          else
            [value, false]
          end
        when 'boolean'
          case value
          when 'true'  then [true, true]
          when 'false' then [false, true]
          else [value, false]
          end
        when 'object'
          if value.is_a?(String) && value.lstrip.start_with?('{')
            begin
              parsed = JSON.parse(value)
              parsed.is_a?(Hash) ? [parsed, true] : [value, false]
            rescue JSON::ParserError
              [value, false]
            end
          else
            [value, false]
          end
        when 'array'
          if value.is_a?(String) && value.lstrip.start_with?('[')
            begin
              parsed = JSON.parse(value)
              parsed.is_a?(Array) ? [parsed, true] : [value, false]
            rescue JSON::ParserError
              [value, false]
            end
          else
            [value, false]
          end
        else
          [value, false]
        end
      end

      def self.schema_properties(tool)
        schema = tool.input_schema
        return nil unless schema

        raw = if schema.respond_to?(:to_h)
                schema.to_h
              elsif schema.respond_to?(:schema)
                schema.schema
              end
        return nil unless raw.is_a?(Hash)

        raw[:properties] || raw['properties']
      end

      def self.rewrite_body(env, body)
        env['rack.input'] = StringIO.new(body)
        env['CONTENT_LENGTH'] = body.bytesize.to_s
      end
    end
  end
end
