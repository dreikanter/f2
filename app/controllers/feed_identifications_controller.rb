class FeedIdentificationsController < ApplicationController
  include StatePolling

  before_action :require_authentication

  rate_limit to: 10, within: 1.minute, by: -> { Current.user.id }, only: :create, with: -> {
    render turbo_stream: turbo_stream.replace(
      "feed-form",
      partial: "feeds/identification_error",
      locals: { input: params[:input], error: "Too many identification attempts. Please wait before trying again." }
    ), status: :too_many_requests
  }

  def create
    if InputClassifier.classify(feed_input) == :malformed
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

      FeedIdentificationJob.perform_later(Current.user.id, feed_input)
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
    original_input = feed_identification.persisted? ? feed_identification.input : feed_input
    feed_identification.destroy if feed_identification.persisted?

    render turbo_stream: turbo_stream.replace(
      "feed-form",
      partial: "feeds/form_collapsed",
      locals: { input: original_input }
    )
  end

  private

  def feed_identification
    @feed_identification ||= FeedIdentification.find_or_initialize_by(user: Current.user, input: feed_input)
  end

  def handle_processing_status
    if feed_identification.invalid_processing?
      feed_identification.destroy
      return render(identification_error(error: "Error identifying feed. Oh no."))
    end

    # Past the deadline: drop the row and show the friendly error so the spinner
    # stops with a message instead of spinning forever.
    if feed_identification.started_at < polling_timeout.ago
      feed_identification.destroy
      return render(identification_error(error: "Feed identification is taking longer than expected. The feed URL may not be responding. Please try again."))
    end

    head :no_content
  end

  def handle_success_status
    suggested = feed_identification.suggested_candidate
    profile_key = suggested&.profile_key
    input_shape = FeedProfile[profile_key]&.dig(:input_shape) || :url
    params_for_input = { input_shape.to_s => feed_identification.input }

    feed = Current.user.feeds.build(
      params: params_for_input,
      feed_profile_key: profile_key,
      name: suggested&.title&.truncate(Feed::NAME_MAX_LENGTH, omission: "…")
    )

    render(identification_success(feed, candidates: feed_identification.candidates))
  end

  def handle_failed_status
    code = feed_identification.error.presence || "generic"
    message = t("feed_identifications.failures.#{code}", default: :"feed_identifications.failures.generic")
    render(identification_error(error: message))
  end

  def identification_error(error:)
    {
      turbo_stream: turbo_stream.replace(
        "feed-form",
        partial: "feeds/identification_error",
        locals: { input: feed_input, error: error }
      )
    }
  end

  def identification_loading
    {
      turbo_stream: turbo_stream.replace(
        "feed-form",
        partial: "feeds/identification_loading",
        locals: { input: feed_input }
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

  def feed_input
    @feed_input ||= params[:input]
  end
end
