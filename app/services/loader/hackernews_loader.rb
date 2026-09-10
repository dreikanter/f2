module Loader
  class HackernewsLoader < HttpBase
    API_URL = "https://hacker-news.firebaseio.com/v0"

    def load
      ids = fetch_json("#{API_URL}/beststories.json")
      ids.map do |id|
        Rails.cache.fetch([self.class.name, id], expires_in: 2.hours) do
          fetch_json("#{API_URL}/item/#{id}.json")
        end
      end
    end

    private

    def fetch_json(url)
      response = http_get(url)
      raise Loader::Error, "HTTP #{response.status}" unless response.success?

      JSON.parse(response.body)
    end
  end
end
