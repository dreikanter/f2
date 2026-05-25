module ApplicationHelper
  def page_header(title, class: nil, &block)
    content_tag :div, class: class_names("d-flex justify-content-between align-items-center mb-4", binding.local_variable_get(:class)) do
      content_tag(:h1, title) + (capture(&block) if block_given?)
    end
  end

  def page_section_header(title, class: nil)
    content_tag(:h2, title, class: class_names("mt-5 mb-4", binding.local_variable_get(:class)))
  end

  def post_content_preview(content, length = 120)
    return "" unless content.present?

    truncate(content.strip, length: length)
  end

  LUCIDE_ICONS = {
    "play"          => '<polygon points="6 3 20 12 6 21 6 3"/>',
    "pause"         => '<rect x="6" y="4" width="4" height="16"/><rect x="14" y="4" width="4" height="16"/>',
    "external-link" => '<path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/><polyline points="15 3 21 3 21 9"/><line x1="10" y1="14" x2="21" y2="3"/>'
  }.freeze

  def lucide_icon(name, css_class: nil, size: "size-9")
    path_data = LUCIDE_ICONS[name]
    return "".html_safe unless path_data

    content_tag(
      :svg,
      path_data.html_safe,
      xmlns: "http://www.w3.org/2000/svg",
      viewBox: "0 0 24 24",
      fill: "none",
      stroke: "currentColor",
      "stroke-width": "2",
      "stroke-linecap": "round",
      "stroke-linejoin": "round",
      "aria-hidden": "true",
      class: class_names(size, "shrink-0", css_class)
    )
  end

  def icon(name, css_class: nil, title: nil, aria_hidden: nil, aria_label: nil)
    options = {
      class: class_names("bi", "bi-#{name}", "inline-block", css_class)
    }
    options[:title] = title if title.present?
    options["aria-hidden"] = aria_hidden.to_s if aria_hidden.present?
    options["aria-label"] = aria_label if aria_label.present?

    content_tag(:i, nil, options)
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

  def navbar_items
    return [] unless Current.user

    items = [
      {
        name: "Status",
        path: status_path,
        active: current_page?(status_path)
      }
    ]

    return items unless Current.user.active?

    items << {
      name: "Feeds",
      path: feeds_path,
      active: current_page?(feeds_path) || controller_path.start_with?("feeds")
    }

    items << {
      name: "Posts",
      path: posts_path,
      active: current_page?(posts_path) || controller_path.start_with?("posts")
    }

    if policy(Event).index?
      items << {
        name: "Admin Panel",
        path: admin_path,
        active: current_page?(admin_path) || controller_path.start_with?("admin")
      }
    end

    items
  end
end
