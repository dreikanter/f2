class LlmClient
  # Bounds one call's tool loop: RubyLLM satisfies tool calls for as long as the
  # model emits them, and both web tools cost money every round.
  #
  # Two stages, and both are needed. Telling the model to stop is advisory — it
  # can call again — so the halt is what actually guarantees termination.
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
