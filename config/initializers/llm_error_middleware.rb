Rails.application.config.to_prepare do
  Faraday::Middleware.register_middleware(llm_errors: LlmClient::ErrorMiddleware)
end
