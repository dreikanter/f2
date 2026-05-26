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

  ICONS = {
    # Media
    "pause"          => '<rect x="14" y="3" width="5" height="18" rx="1"/><rect x="5" y="3" width="5" height="18" rx="1"/>',
    "play"           => '<path d="M5 5a2 2 0 0 1 3.008-1.728l11.997 6.998a2 2 0 0 1 .003 3.458l-12 7A2 2 0 0 1 5 19z"/>',
    # Navigation & actions
    "arrow-down"     => '<path d="M12 5v14"/><path d="m19 12-7 7-7-7"/>',
    "arrow-up"       => '<path d="m5 12 7-7 7 7"/><path d="M12 19V5"/>',
    "chevron-down"   => '<path d="m6 9 6 6 6-6"/>',
    "clipboard"      => '<rect width="8" height="4" x="8" y="2" rx="1" ry="1"/><path d="M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2"/>',
    "external-link"  => '<path d="M15 3h6v6"/><path d="M10 14 21 3"/><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/>',
    "key"            => '<path d="m15.5 7.5 2.3 2.3a1 1 0 0 0 1.4 0l2.1-2.1a1 1 0 0 0 0-1.4L19 4"/><path d="m21 2-9.6 9.6"/><circle cx="7.5" cy="15.5" r="5.5"/>',
    "menu"           => '<path d="M4 5h16"/><path d="M4 12h16"/><path d="M4 19h16"/>',
    "square-pen"     => '<path d="M12 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.375 2.625a1 1 0 0 1 3 3l-9.013 9.014a2 2 0 0 1-.853.505l-2.873.84a.5.5 0 0 1-.62-.62l.84-2.873a2 2 0 0 1 .506-.852z"/>',
    "trash-2"        => '<path d="M10 11v6"/><path d="M14 11v6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6"/><path d="M3 6h18"/><path d="M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/>',
    # Status & indicators
    "circle-check"   => '<circle cx="12" cy="12" r="10"/><path d="m9 12 2 2 4-4"/>',
    "circle-x"       => '<circle cx="12" cy="12" r="10"/><path d="m15 9-6 6"/><path d="m9 9 6 6"/>',
    "clock"          => '<circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/>',
    "file"           => '<path d="M6 22a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h8a2.4 2.4 0 0 1 1.704.706l3.588 3.588A2.4 2.4 0 0 1 20 8v12a2 2 0 0 1-2 2z"/><path d="M14 2v5a1 1 0 0 0 1 1h5"/>',
    "file-image"     => '<path d="M6 22a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h8a2.4 2.4 0 0 1 1.704.706l3.588 3.588A2.4 2.4 0 0 1 20 8v12a2 2 0 0 1-2 2z"/><path d="M14 2v5a1 1 0 0 0 1 1h5"/><circle cx="10" cy="12" r="2"/><path d="m20 17-1.296-1.296a2.41 2.41 0 0 0-3.408 0L9 22"/>',
    "star"           => '<path d="M11.525 2.295a.53.53 0 0 1 .95 0l2.31 4.679a2.123 2.123 0 0 0 1.595 1.16l5.166.756a.53.53 0 0 1 .294.904l-3.736 3.638a2.123 2.123 0 0 0-.611 1.878l.882 5.14a.53.53 0 0 1-.771.56l-4.618-2.428a2.122 2.122 0 0 0-1.973 0L6.396 21.01a.53.53 0 0 1-.77-.56l.881-5.139a2.122 2.122 0 0 0-.611-1.879L2.16 9.795a.53.53 0 0 1 .294-.906l5.165-.755a2.122 2.122 0 0 0 1.597-1.16z"/>',
    "triangle-alert" => '<path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3"/><path d="M12 9v4"/><path d="M12 17h.01"/>',
    # Admin & system
    "calendar"       => '<path d="M8 2v4"/><path d="M16 2v4"/><rect width="18" height="18" x="3" y="4" rx="2"/><path d="M3 10h18"/>',
    "hard-drive"     => '<path d="M10 16h.01"/><path d="M2.212 11.577a2 2 0 0 0-.212.896V18a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-5.527a2 2 0 0 0-.212-.896L18.55 5.11A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"/><path d="M21.946 12.013H2.054"/><path d="M6 16h.01"/>',
    "inbox"          => '<polyline points="22 12 16 12 14 15 10 15 8 12 2 12"/><path d="M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"/>',
    "layers"         => '<path d="M12.83 2.18a2 2 0 0 0-1.66 0L2.6 6.08a1 1 0 0 0 0 1.83l8.58 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83z"/><path d="M2 12a1 1 0 0 0 .58.91l8.6 3.91a2 2 0 0 0 1.65 0l8.58-3.9A1 1 0 0 0 22 12"/><path d="M2 17a1 1 0 0 0 .58.91l8.6 3.91a2 2 0 0 0 1.65 0l8.58-3.9A1 1 0 0 0 22 17"/>',
    "layout-grid"    => '<rect width="7" height="7" x="3" y="3" rx="1"/><rect width="7" height="7" x="14" y="3" rx="1"/><rect width="7" height="7" x="14" y="14" rx="1"/><rect width="7" height="7" x="3" y="14" rx="1"/>',
    "users"          => '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><path d="M16 3.128a4 4 0 0 1 0 7.744"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><circle cx="9" cy="7" r="4"/>'
  }.freeze

  def icon(name, css_class: nil, title: nil, aria_label: nil)
    path_data = ICONS[name]
    return "".html_safe unless path_data

    options = {
      xmlns: "http://www.w3.org/2000/svg",
      viewBox: "0 0 24 24",
      fill: "none",
      stroke: "currentColor",
      "stroke-width": "2",
      "stroke-linecap": "round",
      "stroke-linejoin": "round",
      class: class_names("shrink-0", css_class)
    }

    options[:title] = title if title.present?

    if aria_label.present?
      options["aria-label"] = aria_label
      options[:role] = "img"
    else
      options["aria-hidden"] = "true"
    end

    content_tag(:svg, path_data.html_safe, **options)
  end

  def post_status_icon(status)
    case status.to_s
    when "draft"
      icon("file", css_class: "size-4 text-muted", title: "Draft")
    when "enqueued"
      icon("clock", css_class: "size-4 text-secondary", title: "Enqueued")
    when "rejected"
      icon("circle-x", css_class: "size-4 text-danger", title: "Rejected")
    when "published"
      icon("circle-check", css_class: "size-4 text-success", title: "Published")
    when "failed"
      icon("triangle-alert", css_class: "size-4 text-danger", title: "Failed")
    when "withdrawn"
      icon("trash-2", css_class: "size-4 text-secondary", title: "Withdrawn")
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
