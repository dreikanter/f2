module FeedEntryHelper
  def feed_entry_status_badge_color(status)
    case status.to_s
    when "pending"
      :info
    when "processed"
      :success
    else
      :neutral
    end
  end
end
