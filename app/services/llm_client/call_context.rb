class LlmClient
  class CallContext
    attr_reader :feed, :profile_key, :stage, :model, :purpose

    def initialize(feed:, profile_key:, stage:, model:, purpose: :scheduled_run)
      @feed = feed
      @profile_key = profile_key
      @stage = stage
      @model = model
      @purpose = purpose
    end
  end
end
