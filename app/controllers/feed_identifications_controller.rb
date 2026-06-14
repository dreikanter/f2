class FeedIdentificationsController < ApplicationController
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

  def handle_success_status
    feed = feed_identification.build_recommended_feed(Current.user)
    render(identification_success(feed, candidates: feed_identification.candidates))
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
        locals: { input: feed_input, feed_identification: feed_identification }
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
