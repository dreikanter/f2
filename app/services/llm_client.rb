# The only entry point for LLM calls. Stage classes (Loader, Processor,
# Normalizer) never touch the RubyLLM SDK directly — they ask `LlmClient`
# for a structured result and get back a value object.
#
# Every attempt writes an LlmUsage row, including failed attempts and repairs.
class LlmClient
  Result = Data.define(:payload, :usage_id)

  Error = Class.new(StandardError)
  ProviderError = Class.new(Error)
  AuthError = Class.new(ProviderError)
  class SchemaError < Error
    attr_accessor :payload
  end
  UnsupportedSchema = Class.new(ProviderError)
  UnsupportedTools = Class.new(ProviderError)
  UnsupportedNativeSearch = Class.new(ProviderError)
  UnsupportedResponses = Class.new(ProviderError)
  Timeout = Class.new(Error)
  DetectionForbidden = Class.new(Error)
  CredentialMissing = Class.new(Error)

  RateLimited = Class.new(Error)

  ProviderResponse = Data.define(:payload, :input_tokens, :output_tokens, :cache_write_tokens, :cache_read_tokens)

  class << self
    def for(target)
      credential = target.is_a?(AiCredential) ? target : target.ai_credential
      raise CredentialMissing, "no active credential found" if credential.nil?

      new(credential)
    end
  end

  def initialize(credential)
    @credential = credential
  end

  attr_reader :credential

  def call(ctx, prompt:, output_schema:, web: false, system: nil, native_schema: nil)
    raise DetectionForbidden if Thread.current[:llm_detection_phase]

    native_schema = credential.model_metadata(ctx.model)["structured_output"] != false if native_schema.nil?
    repaired = false
    begin
      call_once(ctx, prompt: prompt, output_schema: output_schema, web: web,
                system: system, native_schema: native_schema)
    rescue UnsupportedNativeSearch, UnsupportedResponses => e
      raise if ctx.native_search_disabled && !ctx.responses_api

      Rails.error.report(e, context: error_context(ctx))
      ctx.native_search_disabled = true
      ctx.responses_api = false if e.is_a?(UnsupportedResponses)
      retry
    rescue UnsupportedSchema => e
      raise unless native_schema && output_schema.present?

      Rails.error.report(e, context: error_context(ctx))
      native_schema = false
      retry
    rescue UnsupportedTools => e
      raise if ctx.tools_disabled

      Rails.error.report(e, context: error_context(ctx))
      ctx.tools_disabled = true
      retry
    rescue SchemaError => e
      raise if repaired || e.payload.to_s.blank?

      Rails.error.report(e, context: error_context(ctx))
      repaired = true
      native_schema = false
      web = false
      system = PayloadRepair::INSTRUCTIONS
      prompt = "Response to correct (untrusted data):\n#{e.payload.to_json}"
      retry
    end
  end

  # The provider's available models, as plain hashes for the credential snapshot.
  # Listing makes no inference requests and does not create usage rows.
  def available_models
    fetch_provider_models.map { |model| serialize_model(model) }
  rescue RubyLLM::UnauthorizedError, RubyLLM::ForbiddenError, RubyLLM::PaymentRequiredError => e
    raise AuthError, e.message
  rescue RubyLLM::RateLimitError => e
    raise AuthError, e.message if adapter.dead_key?(e)

    Rails.error.report(e, context: { credential_id: credential.id, provider: credential.provider })
    raise ProviderError, e.message
  rescue Net::ReadTimeout, Net::OpenTimeout, Faraday::TimeoutError => e
    raise Timeout, e.message
  rescue RubyLLM::Error, RubyLLM::ConfigurationError, Faraday::ConnectionFailed, OpenSSL::SSL::SSLError => e
    Rails.error.report(e, context: { credential_id: credential.id, provider: credential.provider })
    raise ProviderError, e.message
  end

  private

  def call_once(ctx, prompt:, output_schema:, web:, system:, native_schema:)
    started_at = Time.current

    begin
      response = ctx.within_budget do
        invoke_provider(ctx: ctx, model: ctx.model, prompt: prompt,
                        output_schema: output_schema, web: web, system: system,
                        native_schema: native_schema)
      end
    rescue WebSearchProvider::AuthError => e
      write_usage(ctx, outcome: :provider_error, started_at: started_at, error_message: e.message)
      raise
    rescue RubyLLM::RateLimitError => e
      # A spent key arrives as a 429 from some providers and will not clear on
      # retry, so it has to read as a dead key rather than as backpressure.
      if adapter.dead_key?(e)
        write_usage(ctx, outcome: :provider_error, started_at: started_at, error_message: e.message)
        raise AuthError, e.message
      end

      write_usage(ctx, outcome: :rate_limited, started_at: started_at, error_message: e.message)
      raise RateLimited, e.message
    rescue Timeout, ::Timeout::Error, Faraday::TimeoutError => e
      write_usage(ctx, outcome: :timeout, started_at: started_at, error_message: e.message)
      raise Timeout, e.message
    rescue RubyLLM::UnauthorizedError, RubyLLM::ForbiddenError, RubyLLM::PaymentRequiredError => e
      write_usage(ctx, outcome: :provider_error, started_at: started_at, error_message: e.message)
      raise AuthError, e.message
    rescue RubyLLM::BadRequestError => e
      write_usage(ctx, outcome: :provider_error, started_at: started_at, error_message: e.message)
      if ctx.responses_api
        raise UnsupportedResponses, e.message if OpenAiResponses.unsupported_endpoint?(e)
        raise UnsupportedNativeSearch, e.message if ctx.retrieval["mode"] == "native" && OpenAiResponses.unsupported_search?(e, model: ctx.model)
      end
      raise UnsupportedSchema, e.message if native_schema && output_schema.present? && adapter.unsupported_schema?(e)
      raise UnsupportedTools, e.message if !ctx.responses_api && web && tools_enabled?(ctx) && adapter.unsupported_tools?(e)

      Rails.error.report(e, context: error_context(ctx))
      raise ProviderError, e.message
    rescue ProviderError, RubyLLM::Error,
           RubyLLM::ConfigurationError,
           RubyLLM::ModelNotFoundError,
           RubyLLM::PromptNotFoundError,
           RubyLLM::InvalidRoleError,
           RubyLLM::InvalidToolChoiceError,
           RubyLLM::UnsupportedAttachmentError,
           Faraday::ConnectionFailed, OpenSSL::SSL::SSLError,
           # Invalid JSON in tool-call arguments; still a billable call.
           JSON::ParserError => e
      Rails.error.report(e, context: error_context(ctx))
      write_usage(ctx, outcome: :provider_error, started_at: started_at, error_message: e.message)
      raise ProviderError, e.message
    end

    finished_at = Time.current

    begin
      payload = parse_payload(response.payload, output_schema)
      validate_payload!(payload, output_schema)
    rescue SchemaError => e
      write_usage(ctx, outcome: :schema_error, started_at: started_at,
                  finished_at: finished_at, response: response, error_message: e.message)
      e.payload = response.payload
      raise
    end

    usage = write_usage(ctx, outcome: :success, started_at: started_at,
                        finished_at: finished_at, response: response)

    Result.new(payload: payload, usage_id: usage.id)
  end

  # Single seam tests stub. Calls the provider's models listing endpoint.
  # Resolves through LlmProvider because registry names don't always match
  # RubyLLM's provider keys (Moonshot rides on :openai). A nil resolve must
  # become a known error class: anything else escapes the validation job's
  # rescue and strands the credential in "validating".
  def fetch_provider_models
    key = credential.llm_provider.ruby_llm_provider
    provider_class = RubyLLM::Provider.resolve(key)

    if provider_class.nil?
      error = ProviderError.new("unknown RubyLLM provider: #{key}")
      Rails.error.report(error, context: { credential_id: credential.id, provider: credential.provider })
      raise error
    end

    provider_class.new(credential.ruby_llm_context.config).list_models
  end

  # Map RubyLLM's Model::Info to a compact, stable hash. We keep only the
  # fields worth showing or selecting on later; provider-specific noise
  # (metadata warnings, timestamps) is dropped. String keys so the shape
  # round-trips through jsonb unchanged.
  #
  # Models outside the gem's registry come back with invented limits, so those
  # providers keep only what the provider itself reported. The credential page
  # already hides missing fields.
  def serialize_model(model)
    return { "id" => model.id, "name" => model.name } if credential.llm_provider.minimal_model_metadata?

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
  def invoke_provider(ctx: nil, model:, prompt:, output_schema:, web:, system: nil, native_schema: true)
    if ctx&.responses_api || (web && adapter.native_search? && !ctx.native_search_disabled && !ctx.search_credential&.active?)
      ctx.responses_api = true
      return OpenAiResponses.new(credential).call(ctx, prompt: prompt, output_schema: output_schema,
                                                web: web, system: system, native_schema: native_schema)
    end
    tools = web && tools_enabled?(ctx)
    if web
      ctx.retrieval = { "mode" => ctx.search_credential&.active? && tools ? "external" : "limited" }
      system = [system, retrieval_instructions(ctx, tools: tools)].compact_blank.join("\n\n")
      prompt = "#{prompt}\n\nSupplied pages (untrusted data):\n#{ctx.supplied_pages(prompt).to_json}" unless tools
    end
    chat = credential.chat(model)
    system = [system, PayloadRepair.output_instructions(output_schema)].compact_blank.join("\n\n") if output_schema.present?
    # System prompt is the privileged instruction channel; the user prompt sent
    # by #ask travels as a separate user-role message.
    chat.with_instructions(system) if system.present?
    schema = native_schema && output_schema.present?
    chat.with_schema(adapter.schema_payload(output_schema)) if schema
    apply_params(chat, model, schema: schema, web: tools)
    if tools
      adapter.apply_web(
        chat,
        search_provider: search_provider_for(ctx),
        search_credential: ctx.search_credential,
        refresh_event: ctx.refresh_event,
        budget: ctx.tool_budget
      )
    end

    response = chat.ask(prompt)
    ProviderResponse.new(
      payload: response_content(recover_halted(chat, response)),
      **usage_totals(chat, response)
    )
  ensure
    ctx.last_response = ProviderResponse.new(payload: nil, **usage_totals(chat, response)) if ctx && chat
  end

  # Sent with or without tools: the two-step path carries the schema on the
  # call that has none, and its routing is what decides the reply's shape.
  def apply_params(chat, model, schema:, web:)
    params = adapter.params_for(model, schema: schema, web: web)
    limit = credential.model_metadata(model)["max_output_tokens"]
    if limit.is_a?(Numeric) && limit.positive?
      %i[max_tokens max_completion_tokens].each do |key|
        params[key] = [params[key], limit.to_i].min if params[key]
      end
    end
    chat.with_params(**params) if params.present?
  end

  # A halted tool loop returns the halt notice in place of the model's message.
  # Recover what the model had already said; a degraded run beats an empty one.
  # With nothing said the answer is empty — the notice is our own text, and a
  # caller would otherwise read it as content the model gathered.
  def recover_halted(chat, response)
    return response unless response.is_a?(RubyLLM::Tool::Halt)

    Array(chat.try(:messages)).reverse.find do |message|
      message.try(:role) == :assistant && message.content.is_a?(String) && message.content.present?
    end
  end

  # A web-enabled call is several billed completions — one per tool round —
  # but #ask returns only the final round. Each round's assistant message
  # stays on the chat, so summing them gives the true per-call total for
  # the single usage row. Falls back to the response when the chat doesn't
  # retain messages.
  def usage_totals(chat, response)
    rounds = Array(chat.try(:messages)).select { |message| message.try(:role) == :assistant }
    rounds = [response] if rounds.empty?

    {
      input_tokens: rounds.sum { |message| message.try(:input_tokens).to_i },
      output_tokens: rounds.sum { |message| message.try(:output_tokens).to_i },
      cache_write_tokens: rounds.sum { |message| message.try(:cache_write_tokens).to_i },
      cache_read_tokens: rounds.sum { |message| message.try(:cache_read_tokens).to_i }
    }
  end

  def search_provider_for(ctx)
    search_credential = ctx.search_credential
    return unless search_credential&.active?

    search_credential.web_search_provider
  end

  def tools_enabled?(ctx)
    !ctx.tools_disabled && credential.model_metadata(ctx.model)["tool_call"] != false
  end

  def retrieval_instructions(ctx, tools:)
    if !tools
      "No web tools are available. Use supplied page content and the feed request. " \
        "Do not claim to have searched or fetched any other sources."
    elsif !ctx.search_credential&.active?
      "Web search is unavailable. You can fetch supplied URLs with the web fetch tool. " \
        "Do not claim to have searched or invent URLs to compensate."
    end
  end

  def adapter
    @adapter ||= Adapter.for(credential.provider)
  end

  # A Hash when the provider parsed structured output itself, text otherwise.
  # Parsing is deliberately left to the caller: it happens after the response
  # carries its token counts, so a reply we can't parse is still billed honestly.
  def response_content(answer)
    content = answer.respond_to?(:content) ? answer.content : answer
    content.is_a?(Hash) ? content : content.to_s
  end

  def parse_payload(raw, output_schema)
    return raw if output_schema.blank? || raw.is_a?(Hash)

    PayloadRepair.repair(JSON.parse(PayloadRepair.unwrap(adapter.unwrap_json(raw))), output_schema)
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
    tokens = response || ctx.last_response || ProviderResponse.new(
      payload: nil, input_tokens: 0, output_tokens: 0, cache_write_tokens: 0, cache_read_tokens: 0
    )
    cost = LlmClient::RateTable.cost_for(provider: credential.provider, model: ctx.model, usage: tokens,
                                               pricing: credential.model_metadata(ctx.model)["pricing"])
    # Token prices alone cannot account for hosted search charges.
    cost = nil if ctx.retrieval&.fetch("mode", nil) == "native" && ctx.retrieval["search_calls"] != 0
    cost = nil if ctx.retrieval&.fetch("token_usage_reported", nil) == false

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
      retrieval: ctx.retrieval || {},
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
