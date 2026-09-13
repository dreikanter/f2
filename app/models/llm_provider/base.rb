module LlmProvider
  class Base
    def initialize(api_key:)
      @api_key = api_key
    end

    def context
      RubyLLM.context do |config|
        configure(config)
        config.max_retries = 0
      end
    end

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
