module ApplicationHelper
  def page_header(title, &block)
    content_tag :div, class: "d-flex justify-content-between align-items-center mb-4" do
      content_tag(:h1, title) + (capture(&block) if block_given?)
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
      content_tag(:i, nil, class: "bi bi-clock text-secondary", title: "Enqueued")
    when "rejected"
      content_tag(:i, nil, class: "bi bi-x-circle text-danger", title: "Rejected")
    when "published"
      content_tag(:i, nil, class: "bi bi-check-circle-fill text-success", title: "Published")
    when "failed"
      content_tag(:i, nil, class: "bi bi-exclamation-triangle text-danger", title: "Failed")
    when "withdrawn"
      content_tag(:i, nil, class: "bi bi-trash text-secondary", title: "Withdrawn")
    else
      content_tag(:span, status.capitalize, class: "text-muted")
    end
  end

  def highlight_json(json_hash)
    json_string = JSON.pretty_generate(json_hash)
    formatter = Rouge::Formatters::HTML.new(wrap: false)
    lexer = Rouge::Lexers::JSON.new
    highlighted_code = formatter.format(lexer.lex(json_string))
    content_tag(:div, highlighted_code.html_safe, class: "highlight")
  end
end
