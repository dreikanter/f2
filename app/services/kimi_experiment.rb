# Focused Kimi/Moonshot integration experiments (issue #913), run via the
# dev-area jobs runner. Each experiment answers one feasibility question with
# raw evidence, bypassing RubyLLM where the point is to see the wire truth:
#
# - web_search_steps: does Moonshot's builtin `$web_search` engage at all on
#   this endpoint/model, following their documented handshake (declare the
#   builtin -> receive a tool call -> echo its arguments back -> the server
#   executes the search)? Optionally forces the tool via tool_choice.
# - structured_output_attempts: which response_format mode (none /
#   json_object / json_schema) yields parseable JSON, and how often output
#   degrades to markdown-fenced JSON.
# - client_tool_attempt: does Kimi drive a client-side function tool through
#   RubyLLM's loop (the bring-our-own-retrieval path)?
module KimiExperiment
  MODEL = KimiCapabilityProbeJob::MODEL
  DEFAULT_API_BASE = "https://api.moonshot.ai/v1".freeze
  BUILTIN_WEB_SEARCH = { type: "builtin_function", function: { name: "$web_search" } }.freeze
  MAX_HANDSHAKE_ROUNDS = 3
  FENCE = /\A```(?:json)?\s*(.*?)\s*```\z/m

  # Fetches a fixed public page so the model has real retrieval without any
  # model-controlled URL (no SSRF surface). Counts invocations as evidence.
  class FetchRailsBlog < RubyLLM::Tool
    description "Fetches the current content of the Ruby on Rails official blog index page"

    def invocations = @invocations.to_i

    def execute
      @invocations = invocations + 1
      html = Net::HTTP.get(URI("https://rubyonrails.org/blog"))
      html.gsub(%r{<script.*?</script>}mi, " ").gsub(/<[^>]+>/, " ").squish.first(8000)
    end
  end

  class << self
    def web_search_steps(force_tool: false)
      steps = []
      messages = [{ role: "user", content: LlmCapabilityProbe::GATHER_PROMPT }]
      MAX_HANDSHAKE_ROUNDS.times do |round|
        payload = handshake_payload(messages, force_tool: force_tool && round.zero?)
        result = raw_chat(payload)
        choice = result[:body].is_a?(Hash) ? result[:body].dig("choices", 0) : nil
        steps << step_record(round, payload, result, choice)
        break unless choice&.dig("finish_reason") == "tool_calls"

        append_tool_echo(messages, choice["message"])
      end
      steps
    end

    def structured_output_attempts(repeats: 3)
      response_format_modes.flat_map do |mode, format|
        Array.new(repeats) do |attempt|
          payload = { model: MODEL, temperature: 0.2,
                      messages: [{ role: "user", content: structure_prompt }] }
          payload[:response_format] = format if format
          result = raw_chat(payload)
          content = result[:body].is_a?(Hash) ? result[:body].dig("choices", 0, "message", "content").to_s : ""
          { mode: mode, attempt: attempt + 1, status: result[:status], outcome: classify_json(content),
            content: content[0, 500], error: (result[:body].to_json[0, 500] unless result[:status] == 200) }.compact
        end
      end
    end

    def client_tool_attempt
      tool = FetchRailsBlog.new
      chat = LlmCapabilityProbe::Provider.build("moonshot").chat(MODEL).with_tool(tool)
      content = chat.ask("Use the fetch tool to read the Rails blog, then report the two latest post titles with their URLs.").content.to_s
      { invocations: tool.invocations, content: content[0, 1500], grounded: grounded?(content) }
    rescue StandardError => e
      { invocations: tool.invocations, error: "#{e.class}: #{e.message[0, 300]}" }
    end

    def classify_json(text)
      stripped = text.to_s.strip
      return "clean_json" if parseable?(stripped)

      fenced = stripped[FENCE, 1]
      return "fenced_json" if fenced && parseable?(fenced)

      "invalid"
    end

    def grounded?(text)
      text.match?(%r{https?://}) && !LlmCapabilityProbe.refusal?(text)
    end

    def raw_chat(payload)
      base = ENV.fetch("MOONSHOT_API_BASE", DEFAULT_API_BASE)
      uri = URI.parse("#{base.chomp('/')}/chat/completions")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.read_timeout = 240
      request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json",
                                         "Authorization" => "Bearer #{ENV.fetch('MOONSHOT_API_KEY')}")
      request.body = payload.to_json
      response = http.request(request)
      { status: response.code.to_i, body: parse_body(response.body) }
    end

    private

    def handshake_payload(messages, force_tool:)
      payload = { model: MODEL, temperature: 0.6, tools: [BUILTIN_WEB_SEARCH], messages: messages.dup }
      payload[:tool_choice] = { type: "function", function: { name: "$web_search" } } if force_tool
      payload
    end

    # Moonshot's builtin contract: the client acknowledges the tool call by
    # sending its arguments back verbatim; the server then runs the search.
    def append_tool_echo(messages, message)
      messages << message
      Array(message["tool_calls"]).each do |call|
        messages << { role: "tool", tool_call_id: call["id"], name: call.dig("function", "name"),
                      content: call.dig("function", "arguments") }
      end
    end

    def step_record(round, payload, result, choice)
      content = choice&.dig("message", "content").to_s
      { round: round + 1, request: payload.to_json[0, 3000], status: result[:status],
        finish_reason: choice&.dig("finish_reason"),
        tool_calls: choice&.dig("message", "tool_calls")&.to_json&.slice(0, 1000),
        content: content[0, 1500],
        grounded: content.present? && grounded?(content),
        error: (result[:body].to_json[0, 800] unless result[:status] == 200) }.compact
    end

    def response_format_modes
      {
        "none" => nil,
        "json_object" => { type: "json_object" },
        "json_schema" => { type: "json_schema",
                           json_schema: { name: "items", strict: true, schema: LlmCapabilityProbe::PROBE_SCHEMA } }
      }
    end

    def structure_prompt
      LlmCapabilityProbe::STRUCTURE_PROMPT_PREFIX + LlmCapabilityProbe::SAMPLE_TEXT
    end

    def parseable?(text)
      JSON.parse(text)
      true
    rescue JSON::ParserError
      false
    end

    def parse_body(body)
      JSON.parse(body.to_s)
    rescue JSON::ParserError
      body.to_s[0, 800]
    end
  end
end
