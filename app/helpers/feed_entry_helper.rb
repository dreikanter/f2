module FeedEntryHelper
  def feed_entry_status_badge_color(status)
    case status.to_s
    when "pending"
      :blue
    when "processed"
      :green
    else
      :gray
    end
  end
end
