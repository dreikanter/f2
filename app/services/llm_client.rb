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
    fetch_provider_models.map { |model| { "id" => model.id, "name" => model.name } }
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
    rescue UnsupportedNativeSearch => e
      write_usage(ctx, outcome: :provider_error, started_at: started_at, error_message: e.message)
      raise
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
    rescue RubyLLM::Error => e
      write_usage(ctx, outcome: :provider_error, started_at: started_at, error_message: e.message)
      if adapter.capability_error_status?(e) && (!ctx.responses_api || ctx.retrieval["completion_calls"] == 1)
        raise UnsupportedResponses, e.message if ctx.responses_api && adapter.unsupported_responses?(e)
        if %w[native provider].include?(ctx.retrieval["mode"]) && adapter.unsupported_native_search?(e, model: ctx.model)
          ctx.tools_disabled = true if adapter.unsupported_tools?(e)
          raise UnsupportedNativeSearch, e.message
        end
        raise UnsupportedSchema, e.message if native_schema && output_schema.present? && adapter.unsupported_schema?(e)
        raise UnsupportedTools, e.message if web && tools_enabled?(ctx) && adapter.unsupported_tools?(e)
      end

      Rails.error.report(e, context: error_context(ctx))
      raise ProviderError, e.message
    rescue ProviderError,
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

  # Single seam tests stub. Returns a ProviderResponse.
  def invoke_provider(ctx: nil, model:, prompt:, output_schema:, web:, system: nil, native_schema: true)
    tools = web && tools_enabled?(ctx)
    transport = adapter.transport_for(ctx, web: web, tools: tools)
    if transport
      return transport.new(credential).call(ctx, prompt: prompt, output_schema: output_schema,
                                           web: web, system: system, native_schema: native_schema)
    end
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

    ctx.retrieval["token_usage_reported"] = false if ctx
    response = chat.ask(prompt)
    ctx.retrieval["token_usage_reported"] = usage_reported?(chat, response) if ctx
    raise ProviderError, ToolBudget::HALTED if response.is_a?(RubyLLM::Tool::Halt)

    ProviderResponse.new(
      payload: response_content(response),
      **usage_totals(chat, response)
    )
  ensure
    ctx.last_response = ProviderResponse.new(payload: nil, **usage_totals(chat, response)) if ctx && chat
  end

  # Sent with or without tools: the two-step path carries the schema on the
  # call that has none, and its routing is what decides the reply's shape.
  def apply_params(chat, model, schema:, web:)
    params = adapter.params_for(model, schema: schema, web: web)
    limit = OutputLimit.for(credential, model)
    %i[max_tokens max_completion_tokens].each do |key|
      params[key] = [params[key], limit].min if params[key]
    end
    chat.with_params(**params) if params.present?
  end

  # A web-enabled call is several billed completions — one per tool round —
  # but #ask returns only the final round. Each round's assistant message
  # stays on the chat, so summing them gives the true per-call total for
  # the single usage row. Falls back to the response when the chat doesn't
  # retain messages.
  def usage_totals(chat, response)
    rounds = usage_rounds(chat, response)

    {
      input_tokens: rounds.sum { |message| message.try(:input_tokens).to_i },
      output_tokens: rounds.sum { |message| message.try(:output_tokens).to_i },
      cache_write_tokens: rounds.sum { |message| message.try(:cache_write_tokens).to_i },
      cache_read_tokens: rounds.sum { |message| message.try(:cache_read_tokens).to_i }
    }
  end

  def usage_rounds(chat, response)
    rounds = Array(chat.try(:messages)).select { |message| message.try(:role) == :assistant }
    rounds.presence || [response]
  end

  def usage_reported?(chat, response)
    usage_rounds(chat, response).all? do |message|
      %i[input_tokens output_tokens].all? do |field|
        count = message.try(field)
        count.is_a?(Integer) && count >= 0
      end
    end
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
    raise SchemaError, "AI provider returned an empty response" if raw.nil? || (raw.is_a?(String) && raw.blank?)

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
    # Budget checks and free tool discovery can fail before a model request.
    return if ctx.retrieval["completion_calls"] == 0

    finished_at ||= Time.current
    tokens = response || ctx.last_response || ProviderResponse.new(
      payload: nil, input_tokens: 0, output_tokens: 0, cache_write_tokens: 0, cache_read_tokens: 0
    )
    cost = LlmClient::RateTable.cost_for(provider: credential.provider, model: ctx.model, usage: tokens,
                                               pricing: credential.model_metadata(ctx.model)["pricing"])
    cost = nil unless response || ctx.last_response
    # Token prices alone cannot account for hosted search charges.
    cost = nil if %w[native provider].include?(ctx.retrieval["mode"]) && ctx.retrieval["search_calls"] != 0
    cost = nil if ctx.retrieval&.fetch("token_usage_reported", nil) == false
    # A reported total already includes hosted search. nil explicitly means
    # the provider could not supply a complete charge (including BYOK).
    cost = ctx.retrieval["reported_cost_cents"] if ctx.retrieval.key?("reported_cost_cents")

    usage = LlmUsage.create!(
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
    # Each preview event links only the attempts made by that run.
    if ctx.purpose.to_s == "preview" && ctx.refresh_event
      ctx.refresh_event.event_references.create!(reference: usage)
    end
    usage
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
