class RedditPostScore
  class UnavailableError < StandardError; end

  MAX_ATTEMPTS = 3
  POST_PATH = %r{\A/(?:r/[a-z0-9_.]+/)?comments/([a-z0-9]+)(?:[/?#]|\z)}i

  def initialize(instances: nil)
    @instances = instances
  end

  # @param reference [String] Reddit URL, permalink path, base36 ID, or t3_ fullname
  # @return [Integer] reported score; unavailable/hidden scores raise UnavailableError
  def call(reference)
    id = post_id(reference)
    raise ArgumentError, "Expected a Reddit post URL, permalink, ID, or t3_ fullname" unless id

    instances = @instances || RedlibInstances.new.urls.shuffle
    instances.first(MAX_ATTEMPTS).each do |instance|
      score = fetch_score(instance, id)
      return score unless score.nil?
    end

    raise UnavailableError, "No Redlib instance returned a score for #{id}"
  rescue RedlibInstances::Error => e
    raise UnavailableError, e.message
  end

  private

  def post_id(reference)
    input = reference.to_s.strip
    match = input.match(/\A(?:t3_)?([a-z0-9]+)\z/i) ||
            input.match(%r{\Ahttps?://redd\.it/([a-z0-9]+)(?:[/?#]|\z)}i) ||
            input.sub(%r{\Ahttps?://(?:[a-z0-9-]+\.)?reddit\.com(?=/)}i, "").match(POST_PATH)
    match && match[1].downcase
  end

  def fetch_score(instance, id)
    url = "#{instance.delete_suffix('/')}/comments/#{id}/"
    response = http.get(url)
    raise UnavailableError, "Redlib returned HTTP #{response.status}" unless response.success?

    document = Nokogiri::HTML(response.body)
    permalink = document.at_css('meta[property="og:url"]')&.[]("content")
    raise UnavailableError, "Redlib returned a different page" unless post_id(permalink) == id

    # Use the full numeric title, not the rounded visible label (e.g. 2.9k).
    value = document.at_css(".post.highlighted .post_score")&.[]("title")
    score = Integer(value.to_s, 10, exception: false)
    raise UnavailableError, "Redlib returned no numeric post score" if score.nil?

    score
  rescue HttpClient::Error, UnavailableError => e
    Rails.error.report(e, severity: :warning, context: { url: url, post_id: id })
    nil
  end

  def http
    @http ||= HttpClient.build(timeout: 5, max_redirects: 2,
                              validate_url: PublicUrl.method(:safe?), pin_public_address: true)
  end
end
