# Renders why a feed was turned off, from the deterministic reason code in the
# event metadata. Unknown or missing codes fall back to generic copy; the raw
# FreeFeed response (metadata "details") is never rendered.
class FeedTargetGroupUnavailableDescriptionComponent < EventDescriptionComponent
  # Reason codes we have specific copy for. Anything else uses the generic line.
  KNOWN_REASONS = %w[posting_denied group_not_found].freeze

  def call
    I18n.t(
      "events.feed_target_group_unavailable.description_html",
      subject_link: subject_link,
      reason: reason_text
    ).html_safe
  end

  private

  def reason_text
    code = event.metadata["reason"].to_s
    key = KNOWN_REASONS.include?(code) ? code : "generic"
    I18n.t("events.feed_target_group_unavailable.reasons.#{key}")
  end
end
