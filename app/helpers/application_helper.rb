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
    # Media
    "pause"          => '<rect x="6" y="4" width="4" height="16"/><rect x="14" y="4" width="4" height="16"/>',
    "play"           => '<polygon points="6 3 20 12 6 21 6 3"/>',
    # Navigation & actions
    "arrow-down"     => '<path d="M12 5v14"/><path d="m19 12-7 7-7-7"/>',
    "arrow-up"       => '<path d="M12 19V5"/><path d="m5 12 7-7 7 7"/>',
    "chevron-down"   => '<path d="m6 9 6 6 6-6"/>',
    "clipboard"      => '<rect width="8" height="4" x="8" y="2" rx="1" ry="1"/><path d="M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2"/>',
    "external-link"  => '<path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/><polyline points="15 3 21 3 21 9"/><line x1="10" y1="14" x2="21" y2="3"/>',
    "key"            => '<circle cx="7.5" cy="15.5" r="5.5"/><path d="m21 2-9.6 9.6"/><path d="m15.5 7.5 3 3L22 7l-3-3"/>',
    "menu"           => '<line x1="4" x2="20" y1="12" y2="12"/><line x1="4" x2="20" y1="6" y2="6"/><line x1="4" x2="20" y1="18" y2="18"/>',
    "square-pen"     => '<path d="M12 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.375 2.625a1 1 0 0 1 3 3l-9.013 9.014a2 2 0 0 1-.853.505l-2.873.84a.5.5 0 0 1-.62-.62l.84-2.873a2 2 0 0 1 .506-.852z"/>',
    "trash-2"        => '<path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/><line x1="10" x2="10" y1="11" y2="17"/><line x1="14" x2="14" y1="11" y2="17"/>',
    # Status & indicators
    "circle-check"   => '<circle cx="12" cy="12" r="10"/><path d="m9 12 2 2 4-4"/>',
    "circle-x"       => '<circle cx="12" cy="12" r="10"/><path d="m15 9-6 6"/><path d="m9 9 6 6"/>',
    "clock"          => '<circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/>',
    "file"           => '<path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/><path d="M14 2v4a2 2 0 0 0 2 2h4"/>',
    "file-image"     => '<path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/><path d="M14 2v4a2 2 0 0 0 2 2h4"/><circle cx="10" cy="12" r="2"/><path d="m20 17-1.296-1.296a2.41 2.41 0 0 0-3.408 0L9 22"/>',
    "star"           => '<polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/>',
    "triangle-alert" => '<path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3"/><path d="M12 9v4"/><path d="M12 17h.01"/>',
    # Admin & system
    "calendar"       => '<path d="M8 2v4"/><path d="M16 2v4"/><rect width="18" height="18" x="3" y="4" rx="2"/><path d="M3 10h18"/>',
    "hard-drive"     => '<line x1="22" x2="2" y1="12" y2="12"/><path d="M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"/><line x1="6" x2="6.01" y1="16" y2="16"/><line x1="10" x2="10.01" y1="16" y2="16"/>',
    "inbox"          => '<polyline points="22 12 16 12 14 15 10 15 8 12 2 12"/><path d="M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"/>',
    "layers"         => '<path d="m12.83 2.18a2 2 0 0 0-1.66 0L2.6 6.08a1 1 0 0 0 0 1.83l8.58 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83Z"/><path d="m22 17.65-9.17 4.16a2 2 0 0 1-1.66 0L2 17.65"/><path d="m22 12.65-9.17 4.16a2 2 0 0 1-1.66 0L2 12.65"/>',
    "layout-grid"    => '<rect width="7" height="7" x="3" y="3" rx="1"/><rect width="7" height="7" x="14" y="3" rx="1"/><rect width="7" height="7" x="14" y="14" rx="1"/><rect width="7" height="7" x="3" y="14" rx="1"/>',
    "users"          => '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>'
  }.freeze

  def lucide_icon(name, css_class: nil, size: "size-9", title: nil, aria_label: nil)
    path_data = LUCIDE_ICONS[name]
    return "".html_safe unless path_data

    options = {
      xmlns: "http://www.w3.org/2000/svg",
      viewBox: "0 0 24 24",
      fill: "none",
      stroke: "currentColor",
      "stroke-width": "2",
      "stroke-linecap": "round",
      "stroke-linejoin": "round",
      class: class_names(size, "shrink-0", css_class)
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
      lucide_icon("file", css_class: "text-muted", size: "size-4", title: "Draft")
    when "enqueued"
      lucide_icon("clock", css_class: "text-secondary", size: "size-4", title: "Enqueued")
    when "rejected"
      lucide_icon("circle-x", css_class: "text-danger", size: "size-4", title: "Rejected")
    when "published"
      lucide_icon("circle-check", css_class: "text-success", size: "size-4", title: "Published")
    when "failed"
      lucide_icon("triangle-alert", css_class: "text-danger", size: "size-4", title: "Failed")
    when "withdrawn"
      lucide_icon("trash-2", css_class: "text-secondary", size: "size-4", title: "Withdrawn")
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
