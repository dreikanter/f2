class FeedPreviewDescriptionComponent < EventDescriptionComponent
  private

  def description_key
    status = event.metadata["status"]
    if %w[started completed failed interrupted].include?(status)
      "events.feed_preview.#{status}_description_html"
    else
      super
    end
  end
end
