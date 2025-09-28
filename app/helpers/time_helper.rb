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

  def long_time_format(time)
    return nil unless time

    time.strftime("%-d %b %Y, %H:%M")
  end

  def time_ago_tag(time)
    return nil unless time

    content_tag(:time, "#{time_ago_in_words(time, include_seconds: true)} ago",
                datetime: time.rfc3339,
                title: long_time_format(time))
  end
end
