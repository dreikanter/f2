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

    detail = feed_detail

    if detail.success?
      return handle_success_status
    end

    if detail.new_record? || detail.failed?
      detail.assign_attributes(
        status: :processing,
        started_at: Time.current,
        feed_profile_key: nil,
        title: nil,
        error: nil
      )
      detail.save!

      FeedDetailsJob.perform_later(Current.user.id, feed_url)
    end

    render identification_loading
  end

  def show
    detail = feed_detail

    unless detail.persisted?
      return render identification_error(error: "Identification session expired. Please try again.")
    end

    case detail.status
    when "processing"
      handle_processing_status
    when "success"
      handle_success_status
    when "failed"
      handle_failed_status
    end
  end

  private

  def feed_detail
    @feed_detail ||= FeedDetail.find_or_initialize_for(user: Current.user, url: feed_url)
  end

  def valid_url?
    feed_url.present? && feed_url.match?(URI::DEFAULT_PARSER.make_regexp(%w[http https]))
  end

  def handle_processing_status
    detail = feed_detail

    if detail.started_at.nil?
      detail.destroy
      return render identification_error(error: "Identification session is invalid. Please try again.")
    end

    timeout_threshold = IDENTIFICATION_TIMEOUT_SECONDS.seconds

    if Time.current - detail.started_at > timeout_threshold
      detail.destroy
      return render identification_error(error: "Feed identification is taking longer than expected. The feed URL may not be responding. Please try again.")
    end

    render identification_loading
  end

  def handle_success_status
    detail = feed_detail

    feed = Current.user.feeds.build(
      url: detail.url,
      feed_profile_key: detail.feed_profile_key,
      name: detail.title
    )

    render identification_success(feed)
  end

  def handle_failed_status
    detail = feed_detail

    error_message = detail.error.presence || "We couldn't identify a feed profile for this URL."
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

  def feed_url
    @feed_url ||= params[:url]
  end
end
