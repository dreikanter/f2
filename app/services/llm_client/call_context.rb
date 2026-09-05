require "timeout"

class LlmClient
  class CallContext
    MAX_ATTEMPTS = 4

    attr_reader :feed, :profile_key, :stage, :model, :purpose, :search_credential, :refresh_event
    attr_accessor :last_response, :tools_disabled

    def initialize(feed:, profile_key:, stage:, model:, purpose: :scheduled_run,
                   search_credential: nil, refresh_event: nil)
      @feed = feed
      @profile_key = profile_key
      @stage = stage
      @model = model
      @purpose = purpose
      @search_credential = search_credential
      @refresh_event = refresh_event
      @attempts = 0
    end

    def tool_budget
      @tool_budget ||= ToolBudget.new
    end

    def supplied_pages(prompt)
      @supplied_pages ||= SuppliedPages.new(budget: tool_budget).fetch(prompt)
    end

    # Gathering, structuring, and corrections consume the same allowance.
    def within_budget
      self.last_response = nil
      @attempts += 1
      raise LlmClient::Timeout, "AI request attempt budget exceeded" if @attempts > MAX_ATTEMPTS

      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @deadline ||= now + RubyLLM.config.request_timeout
      remaining = @deadline - now
      raise LlmClient::Timeout, "AI request time budget exceeded" unless remaining.positive?

      ::Timeout.timeout(remaining) { yield }
    end
  end
end
