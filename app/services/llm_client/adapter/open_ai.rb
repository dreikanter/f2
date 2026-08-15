class LlmClient
  module Adapter
    # OpenAI needs neither the request tweaks nor the response repair the other
    # providers do: structured outputs come back as clean JSON, and the shared
    # client-side web tools need no extra params. Whether a schema and tools
    # survive the same call is what the capability probe decides, so this stays
    # on Base's two-call fallback until a run says otherwise.
    class OpenAi < Base
    end
  end
end
