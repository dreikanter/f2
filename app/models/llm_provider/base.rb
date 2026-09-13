module LlmProvider
  class Base
    # @param api_key [String] key used to authenticate provider requests
    # @return [Base] provider client bound to the key
    def initialize(api_key:)
      @api_key = api_key
    end

    # @return [RubyLLM::Context] isolated SDK context using this client's key, with retries disabled
    def context
      RubyLLM.context do |config|
        configure(config)
        config.max_retries = 0
      end
    end

    # @abstract Implement provider model discovery.
    # @return [Array<String>] model IDs available to this client's key
    def models
      raise NotImplementedError, "Subclasses must implement #models"
    end

    private

    attr_reader :api_key

    def configure(config)
      raise NotImplementedError, "Subclasses must implement #configure"
    end
  end
end
