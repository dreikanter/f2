module TimeHelper
  def short_time_ago(time)
    return nil unless time

    diff = Time.current - time

    case diff
    when 0..59
      "#{diff.to_i}s"
    when 60..3599
      "#{(diff / 60).to_i}m"
    when 3600..86399
      "#{(diff / 3600).to_i}h"
    when 86400..2591999
      "#{(diff / 86400).to_i}d"
    when 2592000..31535999
      "#{(diff / 2592000).to_i}mo"
    else
      "#{(diff / 31536000).to_i}y"
    end
  end

  def time_ago(time)
    return nil unless time

    diff = Time.current - time

    case diff
    when 0..59
      seconds = diff.to_i
      seconds == 1 ? "1 second ago" : "#{seconds} seconds ago"
    when 60..3599
      minutes = (diff / 60).to_i
      minutes == 1 ? "1 minute ago" : "#{minutes} minutes ago"
    when 3600..86399
      hours = (diff / 3600).to_i
      hours == 1 ? "1 hour ago" : "#{hours} hours ago"
    when 86400..2591999
      days = (diff / 86400).to_i
      days == 1 ? "1 day ago" : "#{days} days ago"
    when 2592000..31535999
      months = (diff / 2592000).to_i
      months == 1 ? "1 month ago" : "#{months} months ago"
    else
      years = (diff / 31536000).to_i
      years == 1 ? "1 year ago" : "#{years} years ago"
    end
  end

  def long_time_format(time)
    return nil unless time

    time.strftime("%-d %b %Y, %H:%M")
  end

  def time_ago_tag(time)
    return nil unless time

    content_tag(:time, time_ago(time),
                datetime: time.rfc3339,
                title: long_time_format(time))
  end
end