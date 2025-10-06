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

  def icon(name, css_class: nil, title: nil)
    classes = ["bi", "bi-#{name}"]
    classes << css_class if css_class.present?
    content_tag(:i, nil, class: classes.join(" "), title: title)
  end

  def post_status_icon(status)
    case status.to_s
    when "draft"
      icon("file-earmark", css_class: "text-muted", title: "Draft")
    when "enqueued"
      icon("clock", css_class: "text-secondary", title: "Enqueued")
    when "rejected"
      icon("x-circle", css_class: "text-danger", title: "Rejected")
    when "published"
      icon("check-circle-fill", css_class: "text-success", title: "Published")
    when "failed"
      icon("exclamation-triangle", css_class: "text-danger", title: "Failed")
    when "withdrawn"
      icon("trash", css_class: "text-secondary", title: "Withdrawn")
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
