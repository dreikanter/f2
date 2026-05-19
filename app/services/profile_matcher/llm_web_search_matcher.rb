module ProfileMatcher
  # Matches free-text queries. Uses AI web search to follow results for
  # the query as if it were an evergreen search subscription.
  class LlmWebSearchMatcher < Base
    input_shape :query
    match_specificity 50
    depends_on_ai true

    def self.profile_key
      "llm_web_search"
    end

    def match?
      return false if input.blank?

      input.length.between?(InputClassifier::QUERY_MIN_LENGTH, InputClassifier::QUERY_MAX_LENGTH)
    end
  end
end
