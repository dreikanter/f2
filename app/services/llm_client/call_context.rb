class LlmClient
  class CallContext
    attr_reader :feed, :profile_key, :stage, :model, :purpose, :search_credential, :refresh_event

    def initialize(feed:, profile_key:, stage:, model:, purpose: :scheduled_run,
                   search_credential: nil, refresh_event: nil)
      @feed = feed
      @profile_key = profile_key
      @stage = stage
      @model = model
      @purpose = purpose
      @search_credential = search_credential
      @refresh_event = refresh_event
    end
  end
end
