module ApplicationHelper
  def page_header(title, &block)
    if block_given?
      content_tag :div, class: "d-flex justify-content-between align-items-center mb-4" do
        content_tag(:h1, title) + capture(&block)
      end
    else
      content_tag :div, class: "mb-4" do
        content_tag :h1, title
      end
    end
  end

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

  def post_content_preview(content, length = 120)
    return "" unless content.present?

    # Truncate to limit HTML size and improve performance
    truncate(content.strip, length: length)
  end
end
