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

  def post_content_preview(content, length = 120)
    return "" unless content.present?

    truncate(content.strip, length: length)
  end

  def post_status_icon(status)
    case status.to_s
    when "draft"
      content_tag(:i, nil, class: "bi bi-file-earmark text-muted", title: "Draft")
    when "enqueued"
      content_tag(:i, nil, class: "bi bi-clock text-warning", title: "Enqueued")
    when "rejected"
      content_tag(:i, nil, class: "bi bi-x-circle text-danger", title: "Rejected")
    when "published"
      content_tag(:i, nil, class: "bi bi-check-circle-fill text-success", title: "Published")
    when "failed"
      content_tag(:i, nil, class: "bi bi-exclamation-triangle text-danger", title: "Failed")
    else
      content_tag(:span, status.capitalize, class: "text-muted")
    end
  end
end
