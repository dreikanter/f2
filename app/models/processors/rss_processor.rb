module Processors
  class RssProcessor < Base
    def process
      # Placeholder for RSS processing logic
      # This would parse XML/RSS content and extract items
      [
        { title: "Sample Article", content: "Sample content", published_at: Time.current },
        { title: "Another Article", content: "More content", published_at: 1.hour.ago }
      ]
    end
  end
end
