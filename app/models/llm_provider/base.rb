module LlmProvider
  class Base
    attr_reader :name, :display_name, :default_model

    def initialize(name:, display_name:, default_model:)
      @name = name
      @display_name = display_name
      @default_model = default_model
    end

    def context(api_key:)
      RubyLLM.context do |config|
        configure(config, api_key)
        config.max_retries = 0
      end
    end

    def models(api_key:)
      raise NotImplementedError, "Subclasses must implement #models"
    end

    private

    def configure(config, api_key)
      raise NotImplementedError, "Subclasses must implement #configure"
    end
  end
end
