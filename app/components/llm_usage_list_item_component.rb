# One retained SDK attempt in an event's AI usage breakdown.
class LlmUsageListItemComponent < ListItemComponent
  OUTCOME_COLORS = {
    "succeeded" => :success,
    "failed" => :danger,
    "cancelled" => :warning,
    "pending" => :neutral
  }.freeze

  def initialize(usage:)
    super()
    @usage = usage
  end

  def before_render
    with_primary { primary_line }
    with_secondary { token_summary }
    with_trailing { trailing_line }
  end

  private

  attr_reader :usage

  def li_data
    { key: "events.llm_usage", llm_usage_id: usage.id }
  end

  def primary_line
    helpers.tag.div(class: "flex min-w-0 items-baseline gap-2") do
      helpers.tag.span(usage.model, class: "truncate font-medium text-heading", data: { key: "events.llm_usage.model" })
    end
  end

  # Cached tokens are only worth the extra clause when a call actually reused
  # cache; most don't, and a "· 0 cached" tail is pure noise.
  def token_summary
    parts = [
      "#{formatted_tokens(usage.input_tokens)} in",
      "#{formatted_tokens(usage.output_tokens)} out"
    ]
    cached = usage.cache_read_tokens.to_i + usage.cache_write_tokens.to_i
    parts << "#{helpers.number_with_delimiter(cached)} cached" if cached.positive?
    parts << "#{helpers.number_with_delimiter(usage.thinking_tokens)} thinking" if usage.thinking_tokens.to_i.positive?
    search_calls = LlmProvider.web_search_call_count(
      provider: usage.provider,
      calls: usage.message&.[](:server_tool_calls)
    )
    parts << "#{search_calls} native web calls" if search_calls&.positive?

    helpers.tag.span(parts.join(" · "), class: "text-sm text-muted tabular-nums", data: { key: "events.llm_usage.tokens" })
  end

  def formatted_tokens(tokens)
    tokens.nil? ? "Unknown" : helpers.number_with_delimiter(tokens)
  end

  def trailing_line
    helpers.tag.div(class: "flex shrink-0 items-center gap-3") do
      helpers.safe_join([
        helpers.tag.span(formatted_cost, class: "text-sm font-medium tabular-nums text-heading", data: { key: "events.llm_usage.cost" }),
        outcome_badge
      ])
    end
  end

  def formatted_cost
    return "Unknown" if usage.total_cost.nil?

    helpers.number_to_currency(usage.total_cost)
  end

  def outcome_badge
    render(BadgeComponent.new(
      text: usage.status.humanize,
      color: OUTCOME_COLORS.fetch(usage.status, :neutral),
      key: "events.llm_usage.outcome"
    ))
  end
end
