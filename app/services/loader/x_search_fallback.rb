module Loader
  class XSearchFallback
    MAX_PROFILES = 20
    MAX_POSTS = 20
    X_SNOWFLAKE_EPOCH_MS = 1_288_834_974_657
    HANDLE_PATH = %r{\A/([A-Za-z0-9_]{1,15})(?:/|\z)}
    RESERVED_HANDLES = %w[i search home explore intent settings share hashtag messages].freeze

    def initialize(chat)
      @chat = chat
      @deadline_at = [chat.deadline_at, 45.seconds.from_now].min
    end

    def candidates
      day = @chat.started_at.utc.beginning_of_day
      handles = source_urls.filter_map do |url|
        uri = URI(url)
        next unless %w[x.com www.x.com].include?(uri.host)

        handle = uri.path.match(HANDLE_PATH)&.captures&.first
        handle unless RESERVED_HANDLES.include?(handle&.downcase)
      rescue URI::InvalidURIError
        nil
      end.uniq.first(MAX_PROFILES)

      ids_by_handle = handles.map do |handle|
        next [] if Time.current >= @deadline_at

        profile_post_ids(handle).select { |id| created_at(id) >= day && created_at(id) <= @chat.started_at }.first(5)
      end
      ids = 5.times.flat_map { |index| ids_by_handle.filter_map { |posts| posts[index] } }.uniq.first(MAX_POSTS)
      ids.filter_map do |id|
        post(id) if Time.current < @deadline_at
      end
    end

    private

    def source_urls
      @chat.messages.flat_map(&:server_tool_calls).flat_map do |call|
        Array(call.input&.dig(:sources)).filter_map { |source| source[:url] }
      end
    end

    def profile_post_ids(handle)
      response = get("https://x.com/#{handle}")
      return [] unless response&.is_a?(Net::HTTPSuccess)

      Nokogiri::HTML(response.body).css("a[href]").filter_map do |link|
        link["href"].match(%r{\A/#{Regexp.escape(handle)}/status/(\d{15,20})(?:/.*)?\z}i)&.captures&.first
      end.uniq.sort_by(&:to_i).reverse
    end

    def post(id)
      response = get("https://x.com/i/status/#{id}", follow_redirect: true)
      return unless response&.is_a?(Net::HTTPSuccess)

      page = Nokogiri::HTML(response.body)
      url = page.at_css('meta[property="og:url"]')&.[]("content")
      published_at = page.at_css('meta[property="article:published_time"]')&.[]("content")
      excerpt = page.at_css('meta[property="og:description"]')&.[]("content")
      source_time = Time.iso8601(published_at) if published_at.present?
      return unless url&.match?(%r{\Ahttps://x\.com/[A-Za-z0-9_]+/status/#{id}\z}) &&
        source_time && (source_time - created_at(id)).abs < 1.minute &&
        source_time >= @chat.started_at.utc.beginning_of_day && source_time <= @chat.started_at &&
        excerpt.present?

      {
        source_url: url,
        published_at: published_at,
        retrieved_at: Time.current.utc.iso8601,
        excerpt: excerpt.truncate(700)
      }
    rescue ArgumentError
      nil
    end

    def created_at(id)
      Time.at(Rational((id.to_i >> 22) + X_SNOWFLAKE_EPOCH_MS, 1_000)).utc
    end

    def get(url, follow_redirect: false)
      uri = URI(url)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 3, read_timeout: 4) do |http|
        http.get(uri.request_uri, { "User-Agent" => "Mozilla/5.0" })
      end
      return response unless follow_redirect && response.is_a?(Net::HTTPRedirection)

      redirected = URI.join(uri, response["location"].to_s)
      return unless redirected.scheme == "https" && redirected.host == "x.com"

      get(redirected.to_s)
    rescue StandardError => error
      Rails.error.report(error, context: { url: url })
      nil
    end
  end
end
