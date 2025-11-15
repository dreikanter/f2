class FeedDetailsController < ApplicationController
  before_action :require_authentication

  IDENTIFICATION_TIMEOUT_SECONDS = 60

  def create
    url = params[:url]

    unless valid_url?(url)
      return render turbo_stream: turbo_stream.replace(
        "feed-form",
        partial: "feeds/identification_error",
        locals: { url: url, error: "Please enter a valid URL" }
      )
    end

    cache_key = feed_identification_cache_key(url)
    cached_data = Rails.cache.read(cache_key)

    if cached_data.nil? || cached_data[:status] != "processing"
      Rails.cache.write(
        cache_key,
        { status: "processing", url: url, started_at: Time.current },
        expires_in: 10.minutes
      )

      FeedIdentificationJob.perform_later(Current.user.id, url)
    end

    render turbo_stream: turbo_stream.replace(
      "feed-form",
      partial: "feeds/identification_loading",
      locals: { url: url }
    )
  end

  def show
    url = params[:url]
    cache_key = feed_identification_cache_key(url)
    cached_data = Rails.cache.read(cache_key)

    if cached_data.nil?
      return render turbo_stream: turbo_stream.replace(
        "feed-form",
        partial: "feeds/identification_error",
        locals: { url: url, error: "Identification session expired. Please try again." }
      )
    end

    case cached_data[:status]
    when "processing"
      handle_processing_status(cached_data, url, cache_key)
    when "success"
      handle_success_status(cached_data)
    when "failed"
      handle_failed_status(cached_data, url)
    end
  end

  private

  def valid_url?(url)
    url.present? && url.match?(URI::DEFAULT_PARSER.make_regexp(%w[http https]))
  end

  def feed_identification_cache_key(url)
    FeedIdentificationCache.key_for(Current.user.id, url)
  end

  def handle_processing_status(cached_data, url, cache_key)
    started_at = cached_data[:started_at] || Time.current
    timeout_threshold = IDENTIFICATION_TIMEOUT_SECONDS.seconds

    if Time.current - started_at > timeout_threshold
      Rails.cache.delete(cache_key)
      return render turbo_stream: turbo_stream.replace(
        "feed-form",
        partial: "feeds/identification_error",
        locals: {
          url: url,
          error: "Feed identification is taking longer than expected. The feed URL may not be responding. Please try again."
        }
      )
    end

    render turbo_stream: turbo_stream.replace(
      "feed-form",
      partial: "feeds/identification_loading",
      locals: { url: url }
    )
  end

  def handle_success_status(cached_data)
    @feed = Current.user.feeds.build(
      url: cached_data[:url],
      feed_profile_key: cached_data[:feed_profile_key],
      name: cached_data[:title]
    )

    render turbo_stream: turbo_stream.replace(
      "feed-form",
      partial: "feeds/form_expanded",
      locals: { feed: @feed }
    )
  end

  def handle_failed_status(cached_data, url)
    error_message = cached_data[:error] || "We couldn't identify a feed profile for this URL."

    render turbo_stream: turbo_stream.replace(
      "feed-form",
      partial: "feeds/identification_error",
      locals: { url: url, error: error_message }
    )
  end
end
