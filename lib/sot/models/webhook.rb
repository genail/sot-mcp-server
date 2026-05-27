module SOT
  class Webhook < Sequel::Model(:_webhooks)
    plugin :timestamps, update_on_create: true
    plugin :validation_helpers

    ALLOWED_METHODS = %w[GET POST PUT PATCH DELETE].freeze

    def validate
      super
      validates_presence [:name, :url, :http_method, :payload_template, :variables]
      validates_unique :name
      validates_includes ALLOWED_METHODS, :http_method, message: "must be one of: #{ALLOWED_METHODS.join(', ')}" if http_method
      validate_template_variable_consistency if payload_template && variables
    end

    def parsed_variables
      variables ? JSON.parse(variables) : []
    end

    def parsed_headers
      headers ? JSON.parse(headers) : {}
    end

    def parsed_allowed_roles
      allowed_roles ? JSON.parse(allowed_roles) : []
    end

    def template_placeholders
      (payload_template || '').scan(/\{\{(\w+)\}\}/).flatten.uniq
    end

    private

    def validate_template_variable_consistency
      vars = begin
        JSON.parse(variables)
      rescue JSON::ParserError
        errors.add(:variables, 'must be valid JSON')
        return
      end

      unless vars.is_a?(Array)
        errors.add(:variables, 'must be a JSON array')
        return
      end

      vars.each do |v|
        unless v.is_a?(Hash) && v['name'] && v['description']
          errors.add(:variables, 'each variable must have name and description')
          return
        end
      end

      defined_names = vars.map { |v| v['name'] }
      placeholders = template_placeholders

      missing_defs = placeholders - defined_names
      extra_defs = defined_names - placeholders

      if missing_defs.any?
        errors.add(:variables, "template uses undefined variables: #{missing_defs.join(', ')}")
      end
      if extra_defs.any?
        errors.add(:variables, "defines variables not in template: #{extra_defs.join(', ')}")
      end
    end
  end
end
