class LlmClient
  # Bounds one call's tool loop. Both web tools are billable — LLM rounds plus
  # search-API calls — and RubyLLM satisfies tool calls for as long as the model
  # keeps emitting them, so a model stuck searching spends without limit.
  #
  # Past the budget the tools stop doing paid work and say so. That alone is
  # advisory: a model can ignore it and call again. So a couple of rounds later
  # the loop is halted outright, which is what actually guarantees termination.
  # The gathered content survives either way (see LlmClient#invoke_provider).
  class ToolBudget
    ROUNDS = 8
    GRACE = 2

    OVER_BUDGET = "Tool budget spent. Answer now using what you have already gathered, " \
                  "and do not call any more tools.".freeze
    HALTED = "Tool budget exceeded; the tool loop was stopped.".freeze

    attr_reader :spent

    def initialize(rounds: ROUNDS, grace: GRACE)
      @rounds = rounds
      @grace = grace
      @spent = 0
    end

    # nil while the caller may do its paid work, otherwise the result the tool
    # must return in its place.
    def claim
      @spent += 1
      return nil if @spent <= @rounds
      return { error: OVER_BUDGET }.to_json if @spent <= @rounds + @grace

      RubyLLM::Tool::Halt.new(HALTED)
    end
  end
end
