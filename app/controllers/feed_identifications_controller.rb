class FeedIdentificationsController < ApplicationController
  before_action :require_authentication

  rate_limit to: 10, within: 1.minute, by: -> { Current.user.id }, only: :create, with: -> {
    render turbo_stream: turbo_stream.replace(
      "feed-form",
      partial: "feeds/identification_error",
      locals: { url: params[:url], error: "Too many identification attempts. Please wait before trying again." }
    ), status: :too_many_requests
  }

  def create
    if InputClassifier.classify(feed_url) == :malformed
      return render(identification_error(error: "Please enter a link, handle, or a few words to search for"))
    end

    return handle_success_status if feed_identification.success?

    if feed_identification.new_record? || feed_identification.failed?
      begin
        feed_identification.update!(
          status: :processing,
          started_at: Time.current,
          candidates: [],
          error: nil
        )
      rescue ActiveRecord::RecordNotUnique
        # Race condition: another process created the record, reload and continue
        feed_identification.reload
      end

      FeedIdentificationJob.perform_later(Current.user.id, feed_url)
    end

    render(identification_loading)
  end

  def show
    unless feed_identification.persisted?
      return render(identification_error(error: "Identification session expired. Please try again."))
    end

    case feed_identification.status
    when "processing"
      handle_processing_status
    when "success"
      handle_success_status
    when "failed"
      handle_failed_status
    end
  end

  def destroy
    original_url = feed_identification.persisted? ? feed_identification.url : feed_url
    feed_identification.destroy if feed_identification.persisted?

    render turbo_stream: turbo_stream.replace(
      "feed-form",
      partial: "feeds/form_collapsed",
      locals: { url: original_url }
    )
  end

  private

  def feed_identification
    @feed_identification ||= FeedIdentification.find_or_initialize_by(user: Current.user, url: feed_url)
  end

  def valid_url?
    feed_url.present? && feed_url.match?(URI::DEFAULT_PARSER.make_regexp(%w[http https]))
  end

  def handle_processing_status
    if feed_identification.invalid_processing?
      feed_identification.destroy
      return render(identification_error(error: "Identification session is invalid. Please try again."))
    end

    if feed_identification.timed_out?
      feed_identification.destroy
      return render(identification_error(error: "Feed identification is taking longer than expected. The feed URL may not be responding. Please try again."))
    end

    render(identification_loading)
  end

  def handle_success_status
    recommended = feed_identification.candidates.first || {}
    profile_key = recommended["profile_key"]
    input_shape = FeedProfile[profile_key]&.dig(:input_shape) || :url
    params_for_input = { input_shape.to_s => feed_identification.url }

    feed = Current.user.feeds.build(
      params: params_for_input,
      feed_profile_key: profile_key,
      name: recommended["title"]
    )

    render(identification_success(feed, candidates: feed_identification.candidates))
  end

  def handle_failed_status
    error_message = feed_identification.error.presence || "We couldn't identify a feed profile for this URL."
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

  def identification_success(feed, candidates: [])
    {
      turbo_stream: turbo_stream.replace(
        "feed-form",
        partial: "feeds/form_expanded",
        locals: { feed: feed, candidates: candidates }
      )
    }
  end

  def feed_url
    @feed_url ||= params[:url]
  end
end
