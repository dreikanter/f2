# The credential contract the capability probes share. Each probe spends one
# operator's key against one live provider, so all that separates the LLM and
# search families is where their credentials live and what to call them.
#
# Including classes pin the provider with a PROVIDER constant and fill in the
# three hooks below.
module ProbesProviderCapability
  extend ActiveSupport::Concern

  class_methods do
    # The credential wears the job's own class name, so what the dev area lists
    # is what to type into the credential form — no second naming to look up.
    def credential_name = name.delete_suffix("Job")

    # Scoped to whoever launched the probe: a run spends that key, and display
    # names are unique per user and provider, so the owner is what makes the
    # name resolve to one credential.
    def credential_for(user)
      credential_scope(user).find_by(provider: self::PROVIDER, display_name: credential_name)
    end

    # Says what to create, since the fix is always the same: one credential,
    # this provider, this exact name.
    def missing_credential_message
      "no #{credential_noun} named #{credential_name.inspect} on your account — " \
        "add #{article_for(provider_label)} #{provider_label} credential " \
        "with that exact name to run this probe"
    end

    # A probe acts on behalf of whoever pressed Run, since it spends their key.
    def runnable_arguments(user) = [user]

    # Where this family keeps its credentials.
    def credential_scope(_user)
      raise NotImplementedError, "#{name} must implement .credential_scope"
    end

    # What to call the credential mid-sentence, e.g. "AI credential".
    def credential_noun
      raise NotImplementedError, "#{name} must implement .credential_noun"
    end

    # The provider's human name, for prose that shouldn't show a config key.
    def provider_label
      raise NotImplementedError, "#{name} must implement .provider_label"
    end

    private

    # Provider labels are proper nouns, so the first letter is all there is to
    # go on — enough for "an Anthropic key" not to read as "a Anthropic key".
    def article_for(word) = word.match?(/\A[aeiou]/i) ? "an" : "a"
  end
end
