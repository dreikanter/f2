module Loader
  # AI extraction entry point for the shared feed pipeline.
  class LlmLoader < Base
    UNAVAILABLE_MESSAGE = "AI feeds are temporarily unavailable.".freeze

    def load
      raise Loader::Error, UNAVAILABLE_MESSAGE
    end
  end
end
