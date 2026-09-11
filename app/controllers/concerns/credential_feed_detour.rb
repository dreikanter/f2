# The feed form sends users here to add a token or credential mid-way through
# creating a feed, round-tripping the draft feed's id so the page can offer a
# way back to the form.
module CredentialFeedDetour
  extend ActiveSupport::Concern

  private

  # The draft feed that detoured here from the feed form, or nil when the page
  # was entered directly.
  def detour_feed
    return nil if params[:feed_id].blank?

    Current.user.feeds.find_by(id: params[:feed_id])
  end
end
