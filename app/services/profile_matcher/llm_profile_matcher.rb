module ProfileMatcher
  # Universal AI fallback. Matches any non-blank input — a URL with no
  # deterministic feed, or a free-text prompt. Lowest specificity, so it always
  # ranks below the structured matchers (RSS, YouTube, …) for the same URL.
  #
  # NOTE: this matcher keeps AI reachable through the current auto-detect flow.
  # Spec §7's structural exclusion (no matcher) lands with the explicit two-mode
  # UX in #909, which replaces matcher-based selection for AI.
  class LlmProfileMatcher < Base
    input_shape :any
    match_specificity 1
    depends_on_ai true

    def match?
      input.present?
    end
  end
end
