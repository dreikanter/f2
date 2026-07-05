# The only entry point for LLM calls. Stage classes (Loader, Processor,
# Normalizer) never touch the RubyLLM SDK directly — they ask `LlmClient`
# for a structured result and get back a value object.
#
# Every call writes exactly one LlmUsage row, on success or on failure,
# so users see honest costs (including failed calls).
class LlmClient
  Result = Data.define(:payload, :usage_id)

  Error = Class.new(StandardError)
  ProviderError = Class.new(Error)
  AuthError = Class.new(ProviderError)
  SchemaError = Class.new(Error)
  Timeout = Class.new(Error)
  DetectionForbidden = Class.new(Error)
  CredentialMissing = Class.new(Error)

  class RateLimited < Error
    attr_accessor :retry_after
  end

  ProviderResponse = Data.define(:payload, :input_tokens, :output_tokens, :cache_write_tokens, :cache_read_tokens)

  class << self
    def for(target, provider = nil)
      credential = resolve_credential(target, provider)
      raise CredentialMissing, "no active credential found" if credential.nil?

      new(credential)
    end

    private

    def resolve_credential(target, provider)
      case target
      when AiCredential
        target
      when Feed
        target.ai_credential || default_credential_for(target.user, provider || LlmProvider.names.first)
      when User
        default_credential_for(target, provider)
      end
    end

    def default_credential_for(user, provider)
      return nil if provider.blank?

      default = user.default_ai_credential
      return default if default&.active? && default.provider == provider

      user.ai_credentials.active.where(provider: provider).order(:id).first
    end
  end

  def initialize(credential)
    @credential = credential
  end

  attr_reader :credential

  def call(ctx, prompt:, output_schema:, web: false)
    raise DetectionForbidden if Thread.current[:llm_detection_phase]

    started_at = Time.current

    begin
      response = invoke_provider(model: ctx.model, prompt: prompt, output_schema: output_schema, web: web)
    rescue RubyLLM::RateLimitError => e
      write_usage(ctx, outcome: :rate_limited, started_at: started_at, error_message: e.message)
      raised = RateLimited.new(e.message)
      raised.retry_after = e.try(:retry_after)
      raise raised
    rescue Net::ReadTimeout, Net::OpenTimeout, Faraday::TimeoutError => e
      write_usage(ctx, outcome: :timeout, started_at: started_at, error_message: e.message)
      raise Timeout, e.message
    rescue RubyLLM::UnauthorizedError, RubyLLM::ForbiddenError, RubyLLM::PaymentRequiredError => e
      write_usage(ctx, outcome: :provider_error, started_at: started_at, error_message: e.message)
      raise AuthError, e.message
    rescue RubyLLM::Error,
           RubyLLM::ConfigurationError,
           RubyLLM::ModelNotFoundError,
           RubyLLM::PromptNotFoundError,
           RubyLLM::InvalidRoleError,
           RubyLLM::InvalidToolChoiceError,
           RubyLLM::UnsupportedAttachmentError => e
      Rails.error.report(e, context: error_context(ctx))
      write_usage(ctx, outcome: :provider_error, started_at: started_at, error_message: e.message)
      raise ProviderError, e.message
    end

    finished_at = Time.current

    begin
      validate_payload!(response.payload, output_schema)
    rescue SchemaError => e
      write_usage(ctx, outcome: :schema_error, started_at: started_at,
                  finished_at: finished_at, response: response, error_message: e.message)
      raise
    end

    usage = write_usage(ctx, outcome: :success, started_at: started_at,
                        finished_at: finished_at, response: response)

    Result.new(payload: response.payload, usage_id: usage.id)
  end

  # The provider's available models, as an array of plain hashes ready to
  # persist on the credential. Doubles as the token-free credential check
  # used by AiCredentialValidationJob: hitting the models endpoint (no
  # inference, no usage row) proves the key works, and a successful fetch
  # is exactly what makes the credential active. Raises a known error
  # class otherwise.
  def available_models
    fetch_provider_models.map { |model| serialize_model(model) }
  rescue RubyLLM::UnauthorizedError, RubyLLM::ForbiddenError, RubyLLM::PaymentRequiredError => e
    raise AuthError, e.message
  rescue RubyLLM::Error, RubyLLM::ConfigurationError => e
    Rails.error.report(e, context: { credential_id: credential.id, provider: credential.provider })
    raise ProviderError, e.message
  end

  private

  # Single seam tests stub. Calls the provider's models listing endpoint.
  def fetch_provider_models
    RubyLLM::Provider.resolve(credential.provider.to_sym)
                     .new(credential.ruby_llm_context.config)
                     .list_models
  end

  # Map RubyLLM's Model::Info to a compact, stable hash. We keep only the
  # fields worth showing or selecting on later; provider-specific noise
  # (metadata warnings, timestamps) is dropped. String keys so the shape
  # round-trips through jsonb unchanged.
  def serialize_model(model)
    {
      "id" => model.id,
      "name" => model.name,
      "family" => model.family,
      "context_window" => model.context_window,
      "max_output_tokens" => model.max_output_tokens,
      "capabilities" => Array(model.capabilities)
    }
  end

  # Single seam tests stub. Returns a ProviderResponse.
  def invoke_provider(model:, prompt:, output_schema:, web:)
    provider = LlmProvider.find(credential.provider)
    chat = credential.ruby_llm_context.chat(
      model: model, provider: provider.ruby_llm_provider, assume_model_exists: provider.assume_model_exists?
    )
    chat.with_schema(output_schema) if output_schema.present? && chat.respond_to?(:with_schema)
    adapter.apply_web(chat, model) if web

    response = chat.ask(prompt)
    ProviderResponse.new(
      payload: output_schema.present? ? parse_payload(response) : response_text(response),
      input_tokens: response.try(:input_tokens).to_i,
      output_tokens: response.try(:output_tokens).to_i,
      cache_write_tokens: response.try(:cached_tokens).to_i,
      cache_read_tokens: response.try(:cache_read_tokens).to_i
    )
  end

  def adapter
    @adapter ||= Adapter.for(credential.provider)
  end

  def response_text(response)
    response.respond_to?(:content) ? response.content.to_s : response.to_s
  end

  def parse_payload(response)
    raw = response.respond_to?(:content) ? response.content : response.to_s
    return raw if raw.is_a?(Hash)

    JSON.parse(adapter.unwrap_json(raw.to_s))
  rescue JSON::ParserError => e
    raise SchemaError, "non-JSON response from provider: #{e.message}"
  end

  def validate_payload!(payload, output_schema)
    return if output_schema.blank?

    errors = JSONSchemer.schema(output_schema).validate(payload).to_a
    return if errors.empty?

    raise SchemaError, "response did not match schema: #{errors.first['error']}"
  end

  def write_usage(ctx, outcome:, started_at:, finished_at: nil, response: nil, error_message: nil)
    finished_at ||= Time.current
    tokens = response || ProviderResponse.new(
      payload: nil, input_tokens: 0, output_tokens: 0, cache_write_tokens: 0, cache_read_tokens: 0
    )
    cost = LlmClient::RateTable.cost_for(
      provider: credential.provider,
      model: ctx.model,
      usage: LlmClient::RateTable::Usage.new(
        input_tokens: tokens.input_tokens,
        output_tokens: tokens.output_tokens,
        cache_write_tokens: tokens.cache_write_tokens,
        cache_read_tokens: tokens.cache_read_tokens
      )
    )

    LlmUsage.create!(
      user: credential.user,
      feed: ctx.feed,
      ai_credential: credential,
      profile_key: ctx.profile_key,
      stage: ctx.stage,
      purpose: ctx.purpose,
      provider: credential.provider,
      model: ctx.model,
      input_tokens: tokens.input_tokens,
      output_tokens: tokens.output_tokens,
      cache_write_tokens: tokens.cache_write_tokens,
      cache_read_tokens: tokens.cache_read_tokens,
      cost_estimate_cents: cost,
      outcome: outcome,
      started_at: started_at,
      finished_at: finished_at,
      duration_ms: ((finished_at - started_at) * 1000).round,
      error_message: error_message
    )
  end

  def error_context(ctx)
    {
      feed_id: ctx.feed&.id,
      profile_key: ctx.profile_key,
      provider: credential.provider,
      model: ctx.model,
      stage: ctx.stage,
      purpose: ctx.purpose
    }
  end
end
