# One row of an event's per-call AI usage breakdown: the model and stage, the
# token counts, and the call's cost and outcome.
class LlmUsageListItemComponent < ListItemComponent
  # Unsuccessful requests may still incur charges.
  OUTCOME_COLORS = {
    "success" => :success,
    "schema_error" => :danger,
    "provider_error" => :danger,
    "rate_limited" => :warning,
    "timeout" => :warning,
    "pending" => :neutral,
    "interrupted" => :warning
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
      helpers.safe_join([
        helpers.tag.span(usage.model, class: "truncate font-medium text-heading", data: { key: "events.llm_usage.model" }),
        stage_label
      ].compact)
    end
  end

  def stage_label
    return if usage.stage.blank?

    helpers.tag.span(usage.stage.humanize(capitalize: false),
                     class: "shrink-0 text-sm text-muted", data: { key: "events.llm_usage.stage" })
  end

  def token_summary
    parts = [
      "#{formatted_tokens(usage.input_tokens)} in",
      "#{formatted_tokens(usage.output_tokens)} out"
    ]
    if usage.cache_read_tokens.nil? || usage.cache_write_tokens.nil?
      parts << "cache usage unknown"
    else
      cached = usage.cache_read_tokens + usage.cache_write_tokens
      parts << "#{formatted_tokens(cached)} cached" if cached.positive?
    end
    if %w[native provider].include?(usage.retrieval["mode"])
      calls = usage.retrieval["search_calls"]
      kind = usage.retrieval["mode"]
      parts << (calls.nil? ? "#{kind} search usage unknown" : "#{calls} #{kind} web calls")
    elsif usage.retrieval["mode"] == "limited"
      parts << "web search unavailable"
    end

    helpers.tag.span(parts.join(" · "), class: "text-sm text-muted tabular-nums", data: { key: "events.llm_usage.tokens" })
  end

  def formatted_tokens(count)
    count.nil? ? "Unknown" : helpers.number_with_delimiter(count)
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
    return "Unknown" if usage.cost_estimate_cents.nil?

    helpers.number_to_currency(usage.cost_estimate_cents / 100.0)
  end

  def outcome_badge
    render(BadgeComponent.new(
      text: usage.outcome.humanize,
      color: OUTCOME_COLORS.fetch(usage.outcome, :neutral),
      key: "events.llm_usage.outcome"
    ))
  end
end
