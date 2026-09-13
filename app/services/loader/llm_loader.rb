module Loader
  # AI feed pipeline entry point. Currently rejects loading while extraction
  # is unavailable.
  class LlmLoader < Base
    UNAVAILABLE_MESSAGE = "AI feeds are temporarily unavailable.".freeze

    def load
      raise Loader::Error, UNAVAILABLE_MESSAGE
    end
  end
end
