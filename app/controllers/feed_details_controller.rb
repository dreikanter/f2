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
      return render(identification_error(error: "Please enter a valid URL"))
    end

    return handle_success_status if feed_detail.success?

    if feed_detail.new_record? || feed_detail.failed?
      begin
        feed_detail.update!(
          status: :processing,
          started_at: Time.current,
          feed_profile_key: nil,
          title: nil,
          error: nil
        )
      rescue ActiveRecord::RecordNotUnique
        # Race condition: another process created the record, reload and continue
        feed_detail.reload
      end

      FeedDetailsJob.perform_later(Current.user.id, feed_url)
    end

    render(identification_loading)
  end

  def show
    unless feed_detail.persisted?
      return render(identification_error(error: "Identification session expired. Please try again."))
    end

    case feed_detail.status
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
    @feed_detail ||= FeedDetail.find_or_initialize_by(user: Current.user, url: feed_url)
  end

  def valid_url?
    feed_url.present? && feed_url.match?(URI::DEFAULT_PARSER.make_regexp(%w[http https]))
  end

  def handle_processing_status
    if feed_detail.started_at.nil?
      feed_detail.destroy
      return render(identification_error(error: "Identification session is invalid. Please try again."))
    end

    timeout_threshold = IDENTIFICATION_TIMEOUT_SECONDS.seconds

    if Time.current - feed_detail.started_at > timeout_threshold
      feed_detail.destroy
      return render(identification_error(error: "Feed identification is taking longer than expected. The feed URL may not be responding. Please try again."))
    end

    render(identification_loading_poll)
  end

  def handle_success_status
    feed = Current.user.feeds.build(
      url: feed_detail.url,
      feed_profile_key: feed_detail.feed_profile_key,
      name: feed_detail.title
    )

    render(identification_success(feed))
  end

  def handle_failed_status
    error_message = feed_detail.error.presence || "We couldn't identify a feed profile for this URL."
    render(identification_error(error: error_message))
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

  def identification_loading_poll
    {
      turbo_stream: turbo_stream.replace(
        "feed-form",
        partial: "feeds/identification_loading_poll"
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
