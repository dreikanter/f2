class LlmClient
  module Adapter
    # OpenAI-compatible providers reject a structured-output request the same
    # way, so the adapters in front of them share one matcher.
    module SchemaRejection
      def unsupported_schema?(error)
        detail = error_detail(error)
        return false unless detail.is_a?(Hash) && %w[response_format text.format text.format.type].include?(detail["param"])

        detail["code"] == "unsupported_parameter" ||
          detail["message"].to_s.match?(/\AInvalid parameter: '(?:response_format|text.format)' of type 'json_schema' is not supported with (?:this )?model\b/i)
      end
    end
  end
end
