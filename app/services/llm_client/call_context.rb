class LlmClient
  class CallContext
    attr_reader :feed, :profile_key, :stage, :model, :purpose, :search_credential

    def initialize(feed:, profile_key:, stage:, model:, purpose: :scheduled_run, search_credential: nil)
      @feed = feed
      @profile_key = profile_key
      @stage = stage
      @model = model
      @purpose = purpose
      @search_credential = search_credential
    end
  end
end
