# Explicit "try again" on an existing preview. The row already holds the source
# and AI selections, so a refresh needs nothing from the request but its id.
class FeedPreviews::RefreshesController < ApplicationController
  include PreviewSearchCredential

  def create
    preview = Current.user.feed_previews.find(params[:feed_preview_id])
    preview.restart!(search_credential_id: resolve_search_credential(preview.feed_profile_key)&.id)

    render turbo_stream: turbo_stream.update(
      "feed-preview-body",
      partial: "feed_previews/processing",
      locals: { preview: preview }
    )
  end
end
