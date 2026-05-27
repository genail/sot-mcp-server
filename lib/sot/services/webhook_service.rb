require 'net/http'
require 'uri'
require 'json'

module SOT
  class WebhookService
    class ValidationError < StandardError; end

    TIMEOUT = 10
    HTTP_CLASSES = {
      'GET' => Net::HTTP::Get,
      'POST' => Net::HTTP::Post,
      'PUT' => Net::HTTP::Put,
      'PATCH' => Net::HTTP::Patch,
      'DELETE' => Net::HTTP::Delete
    }.freeze

    def self.render_template(template, values)
      placeholders = template.scan(/\{\{(\w+)\}\}/).flatten.uniq
      missing = placeholders - values.keys
      raise ValidationError, "Missing variable values: #{missing.join(', ')}" if missing.any?

      result = template.dup
      placeholders.each do |name|
        result.gsub!("{{#{name}}}", values[name].to_s)
      end
      result
    end

    def self.can_call?(user, webhook)
      return true if user.admin?
      webhook.parsed_allowed_roles.include?(user.role.name)
    end

    def self.call_webhook(webhook:, user:, variable_values:)
      rendered_body = render_template(webhook.payload_template, variable_values)
      uri = URI(webhook.url)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = TIMEOUT
      http.read_timeout = TIMEOUT

      request_class = HTTP_CLASSES[webhook.http_method]
      request = request_class.new(uri.request_uri)

      webhook.parsed_headers.each { |k, v| request[k] = v }

      unless webhook.http_method == 'GET'
        request['Content-Type'] ||= 'application/json'
        request.body = rendered_body
      end

      response = http.request(request)
      status_code = response.code.to_i
      success = status_code >= 200 && status_code < 300

      WebhookLog.create(
        webhook_id: webhook.id,
        user_id: user.id,
        variable_values: JSON.generate(variable_values),
        status_code: status_code,
        response_body: response.body,
        success: success
      )

      { success: success, status_code: status_code }
    rescue ValidationError
      raise
    rescue StandardError => e
      WebhookLog.create(
        webhook_id: webhook.id,
        user_id: user.id,
        variable_values: JSON.generate(variable_values),
        success: false,
        error_message: "#{e.class}: #{e.message}"
      )

      { success: false, status_code: nil, error: "#{e.class}: #{e.message}" }
    end
  end
end
