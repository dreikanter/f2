class FeedDetailsController < ApplicationController
  before_action :require_authentication

  IDENTIFICATION_TIMEOUT_SECONDS = 30

  rate_limit to: 10, within: 1.minute, by: -> { Current.user.id }, only: :create, with: -> {
    render turbo_stream: turbo_stream.replace(
      "feed-form",
      partial: "feeds/identification_error",
      locals: { url: params[:url], error: "Too many identification attempts. Please wait before trying again." }
    ), status: :too_many_requests
  }

  def create
    unless valid_url?
      return render identification_error(error: "Please enter a valid URL")
    end

    if identification_status == "success"
      return handle_success_status
    end

    if identification_status.nil? || identification_status == "failed"
      data = {
        status: "processing",
        url: feed_url,
        started_at: Time.current
      }

      Rails.cache.write(cache_key, data, expires_in: 10.minutes)
      FeedDetailsJob.perform_later(Current.user.id, feed_url)
    end

    render identification_loading
  end

  def show
    if cached_data.nil?
      return render identification_error(error: "Identification session expired. Please try again.")
    end

    case cached_data[:status]
    when "processing"
      handle_processing_status
    when "success"
      handle_success_status
    when "failed"
      handle_failed_status
    end
  end

  private

  def cache_key
    @cache_key ||= FeedIdentificationCache.key_for(Current.user.id, feed_url)
  end

  def cached_data
    @cached_data ||= Rails.cache.read(cache_key)
  end

  def valid_url?
    feed_url.present? && feed_url.match?(URI::DEFAULT_PARSER.make_regexp(%w[http https]))
  end

  def handle_processing_status
    started_at = cached_data[:started_at]

    if started_at.nil?
      Rails.cache.delete(cache_key)
      return render identification_error(error: "Identification session is invalid. Please try again.")
    end

    timeout_threshold = IDENTIFICATION_TIMEOUT_SECONDS.seconds

    if Time.current - started_at > timeout_threshold
      Rails.cache.delete(cache_key)
      return render identification_error(error: "Feed identification is taking longer than expected. The feed URL may not be responding. Please try again.")
    end

    render identification_loading
  end

  def handle_success_status
    feed = Current.user.feeds.build(
      url: cached_data[:url],
      feed_profile_key: cached_data[:feed_profile_key],
      name: cached_data[:title]
    )

    render identification_success(feed)
  end

  def handle_failed_status
    error_message = cached_data[:error] || "We couldn't identify a feed profile for this URL."
    render identification_error(error: error_message)
  end

  def identification_error(error:)
    {
      turbo_stream: turbo_stream.replace(
        "feed-form",
        partial: "feeds/identification_error",
        locals: { url: feed_url, error: error }
      )
    }
  end

  def identification_loading
    {
      turbo_stream: turbo_stream.replace(
        "feed-form",
        partial: "feeds/identification_loading",
        locals: { url: feed_url }
      )
    }
  end

  def identification_success(feed)
    {
      turbo_stream: turbo_stream.replace(
        "feed-form",
        partial: "feeds/form_expanded",
        locals: { feed: feed }
      )
    }
  end

  def identification_status
    cached_data&.dig(:status)
  end

  def feed_url
    @feed_url ||= params[:url]
  end
end
