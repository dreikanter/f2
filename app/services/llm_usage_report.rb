# Reports retained SDK attempts. Interrupted requests may leave no usage row;
# these totals describe recorded usage, not every request sent to a provider.
class LlmUsageReport
  STATS_PERIOD = 30.days
  PERIODS = { day: 1.day, week: 1.week, month: STATS_PERIOD }.freeze

  Totals = Data.define(:call_count, :known_cost, :unknown_cost_count,
                       :input_tokens, :output_tokens, :cache_read_tokens,
                       :cache_write_tokens, :thinking_tokens) do
    def incomplete?
      unknown_cost_count.positive?
    end

    def total_cost
      known_cost unless incomplete?
    end

    def event_stats
      return {} if call_count.zero?

      # Event snapshots use cents and JSON numbers; SDK costs are USD decimals.
      { llm_calls: call_count, llm_cost_cents: total_cost && (total_cost * 100).to_f }
    end
  end

  attr_reader :usages

  def self.for_event(event)
    chat_ids = event.event_references.where(reference_type: "LlmChat").select(:reference_id)
    new(chats: LlmChat.where(id: chat_ids))
  end

  def self.for_feed(feed, period: nil)
    new(chats: feed.llm_chats, period: period)
  end

  def self.for_credential(credential, period: nil)
    new(chats: credential.llm_chats, period: period)
  end

  # @param chats [ActiveRecord::Relation<LlmChat>] attribution scope
  # @param period [Range<Time>, nil] usage timestamps to include
  def initialize(chats:, period: nil)
    # A subquery keeps each usage row unique even with duplicate event references.
    @usages = RubyLLM::ActiveRecord::Usage.where(chat_type: "LlmChat", chat_id: chats.select(:id))
    @usages = @usages.where(created_at: period) if period
  end

  def totals
    summarize(usages)
  end

  # Rolling windows end at now; attribution uses usage time, not chat creation.
  def totals_for_periods(now: Time.current)
    PERIODS.transform_values { |period| summarize(usages.where(created_at: (now - period)..now)) }
  end

  private

  def summarize(scope)
    values = scope.pick(Arel.sql(<<~SQL.squish))
      COUNT(*), COALESCE(SUM(total_cost), 0), COUNT(*) - COUNT(total_cost),
      SUM(input_tokens), SUM(output_tokens), SUM(cache_read_tokens),
      SUM(cache_write_tokens), SUM(thinking_tokens)
    SQL
    Totals.new(*values)
  end
end
