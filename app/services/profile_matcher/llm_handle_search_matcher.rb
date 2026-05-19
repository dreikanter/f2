module ProfileMatcher
  # Matches social-style handles (`@user` or `@user@instance`). Uses
  # AI search to follow the named account. Mid specificity so it ranks
  # below structured handle providers (none yet) but above generic
  # web-search.
  class LlmHandleSearchMatcher < Base
    input_shape :handle
    match_specificity 50
    depends_on_ai true

    def self.profile_key
      "llm_handle_search"
    end

    def match?
      return false if input.blank?

      input.match?(InputClassifier::HANDLE_REGEX)
    end
  end
end
