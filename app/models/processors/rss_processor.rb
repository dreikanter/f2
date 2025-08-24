module Processors
  class RssProcessor < Base
    def self.display_name
      "RSS/XML"
    end

    def process
      # TBD
      [
        { title: "Sample Article", content: "Sample content", published_at: Time.current },
        { title: "Another Article", content: "More content", published_at: 1.hour.ago }
      ]
    end
  end
end
