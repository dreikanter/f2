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

    truncate(content.strip, length: length, omission: "…")
  end

  # Decorative separator between card footer items. Hidden from assistive tech
  # so the items read as distinct entries rather than "dot".
  def middot
    content_tag(:span, "·", class: "mx-1 text-slate-300", aria: { hidden: true })
  end

  ICONS = {
    # Navigation & actions
    "arrow-down"     => '<path d="M12 5v14"/><path d="m19 12-7 7-7-7"/>',
    "arrow-up"       => '<path d="m5 12 7-7 7 7"/><path d="M12 19V5"/>',
    "chevron-down"   => '<path d="m6 9 6 6 6-6"/>',
    "chevron-right"  => '<path d="m9 18 6-6-6-6"/>',
    "clipboard"      => '<rect width="8" height="4" x="8" y="2" rx="1" ry="1"/><path d="M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2"/>',
    "external-link"  => '<path d="M15 3h6v6"/><path d="M10 14 21 3"/><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/>',
    "key"            => '<path d="m15.5 7.5 2.3 2.3a1 1 0 0 0 1.4 0l2.1-2.1a1 1 0 0 0 0-1.4L19 4"/><path d="m21 2-9.6 9.6"/><circle cx="7.5" cy="15.5" r="5.5"/>',
    "key-square"     => '<path d="M12.4 2.7a2.5 2.5 0 0 1 3.4 0l5.5 5.5a2.5 2.5 0 0 1 0 3.4l-3.7 3.7a2.5 2.5 0 0 1-3.4 0L8.7 9.8a2.5 2.5 0 0 1 0-3.4z"/><path d="m14 7 3 3"/><path d="m9.4 10.6-6.814 6.814A2 2 0 0 0 2 18.828V21a1 1 0 0 0 1 1h3a1 1 0 0 0 1-1v-1a1 1 0 0 1 1-1h1a1 1 0 0 0 1-1v-1a1 1 0 0 1 1-1h.172a2 2 0 0 0 1.414-.586l.814-.814"/>',
    "lock"           => '<rect width="18" height="11" x="3" y="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>',
    "sparkles"       => '<path d="m12 3-1.912 5.813a2 2 0 0 1-1.275 1.275L3 12l5.813 1.912a2 2 0 0 1 1.275 1.275L12 21l1.912-5.813a2 2 0 0 1 1.275-1.275L21 12l-5.813-1.912a2 2 0 0 1-1.275-1.275z"/><path d="M5 3v4"/><path d="M19 17v4"/><path d="M3 5h4"/><path d="M17 19h4"/>',
    "refresh-ccw"    => '<path d="M21 12a9 9 0 0 0-9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/><path d="M3 3v5h5"/><path d="M3 12a9 9 0 0 0 9 9 9.75 9.75 0 0 0 6.74-2.74L21 16"/><path d="M16 16h5v5"/>',
    "loader-circle"  => '<path d="M21 12a9 9 0 1 1-6.219-8.56"/>',
    "menu"           => '<path d="M4 5h16"/><path d="M4 12h16"/><path d="M4 19h16"/>',
    "trash-2"        => '<path d="M10 11v6"/><path d="M14 11v6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6"/><path d="M3 6h18"/><path d="M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/>',
    # Status & indicators
    "circle-check"   => '<circle cx="12" cy="12" r="10"/><path d="m9 12 2 2 4-4"/>',
    "circle-x"       => '<circle cx="12" cy="12" r="10"/><path d="m15 9-6 6"/><path d="m9 9 6 6"/>',
    "circle-play"    => '<circle cx="12" cy="12" r="10"/><polygon points="10 8 16 12 10 16 10 8"/>',
    "circle-pause"   => '<circle cx="12" cy="12" r="10"/><line x1="10" x2="10" y1="15" y2="9"/><line x1="14" x2="14" y1="15" y2="9"/>',
    "circle-dashed"  => '<path d="M10.1 2.18a9.93 9.93 0 0 1 3.8 0"/><path d="M17.6 3.71a9.95 9.95 0 0 1 2.69 2.7"/><path d="M21.82 10.1a9.93 9.93 0 0 1 0 3.8"/><path d="M20.29 17.6a9.95 9.95 0 0 1-2.7 2.69"/><path d="M13.9 21.82a9.94 9.94 0 0 1-3.8 0"/><path d="M6.4 20.29a9.95 9.95 0 0 1-2.69-2.7"/><path d="M2.18 13.9a9.93 9.93 0 0 1 0-3.8"/><path d="M3.71 6.4a9.95 9.95 0 0 1 2.7-2.69"/>',
    "square"         => '<rect width="18" height="18" x="3" y="3" rx="2"/>',
    "square-check-big" => '<path d="M21 10.656V19a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h12.344"/><path d="m9 11 3 3L22 4"/>',
    "clock"          => '<circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/>',
    "file"           => '<path d="M6 22a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h8a2.4 2.4 0 0 1 1.704.706l3.588 3.588A2.4 2.4 0 0 1 20 8v12a2 2 0 0 1-2 2z"/><path d="M14 2v5a1 1 0 0 0 1 1h5"/>',
    "info"           => '<circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/>',
    "triangle-alert" => '<path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3"/><path d="M12 9v4"/><path d="M12 17h.01"/>',
    # Admin & system
    "calendar"       => '<path d="M8 2v4"/><path d="M16 2v4"/><rect width="18" height="18" x="3" y="4" rx="2"/><path d="M3 10h18"/>',
    "hard-drive"     => '<path d="M10 16h.01"/><path d="M2.212 11.577a2 2 0 0 0-.212.896V18a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-5.527a2 2 0 0 0-.212-.896L18.55 5.11A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"/><path d="M21.946 12.013H2.054"/><path d="M6 16h.01"/>',
    "hard-hat"       => '<path d="M2 18a1 1 0 0 0 1 1h18a1 1 0 0 0 1-1v-2a1 1 0 0 0-1-1H3a1 1 0 0 0-1 1v2z"/><path d="M10 10V5a1 1 0 0 1 1-1h2a1 1 0 0 1 1 1v5"/><path d="M4 15V9a8 8 0 0 1 16 0v6"/>',
    "inbox"          => '<polyline points="22 12 16 12 14 15 10 15 8 12 2 12"/><path d="M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"/>',
    "mail"           => '<rect width="20" height="16" x="2" y="4" rx="2"/><path d="m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7"/>',
    "layers"         => '<path d="M12.83 2.18a2 2 0 0 0-1.66 0L2.6 6.08a1 1 0 0 0 0 1.83l8.58 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83z"/><path d="M2 12a1 1 0 0 0 .58.91l8.6 3.91a2 2 0 0 0 1.65 0l8.58-3.9A1 1 0 0 0 22 12"/><path d="M2 17a1 1 0 0 0 .58.91l8.6 3.91a2 2 0 0 0 1.65 0l8.58-3.9A1 1 0 0 0 22 17"/>',
    "layout-grid"    => '<rect width="7" height="7" x="3" y="3" rx="1"/><rect width="7" height="7" x="14" y="3" rx="1"/><rect width="7" height="7" x="14" y="14" rx="1"/><rect width="7" height="7" x="3" y="14" rx="1"/>',
    "users"          => '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><path d="M16 3.128a4 4 0 0 1 0 7.744"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><circle cx="9" cy="7" r="4"/>',
    # Search
    "search"         => '<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>',
    # Posts
    "ellipsis"        => '<circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/><circle cx="5" cy="12" r="1"/>'
  }.freeze

  def icon(name, css_class: nil, title: nil, aria_label: nil)
    path_data = ICONS[name]
    return "".html_safe unless path_data

    options = {
      xmlns: "http://www.w3.org/2000/svg",
      viewBox: "0 0 24 24",
      width: "24",
      height: "24",
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

  # Status icon for records sharing the pending/validating/active/inactive
  # lifecycle (access tokens, AI credentials). Mirrors feed_status_icon's role
  # as the leading glyph in a list row.
  def credential_status_icon(status)
    case status.to_s
    when "active"
      icon("circle-check", css_class: "size-4 text-emerald-500", title: "Active", aria_label: "Active")
    when "inactive"
      icon("circle-x", css_class: "size-4 text-red-500", title: "Inactive", aria_label: "Inactive")
    else
      icon("loader-circle", css_class: "size-4 text-faint", title: "Checking", aria_label: "Checking")
    end
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

  def system_check_icon(status)
    case status.to_sym
    when :ok
      icon("square-check-big", css_class: "size-5 text-green-600", aria_label: "OK")
    when :error
      icon("square", css_class: "size-5 text-red-600", aria_label: "Problem")
    else
      icon("square", css_class: "size-5 text-faint", aria_label: "Not set")
    end
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

    if policy(:access).dev?
      items << {
        name: "Dev Tools",
        path: development_path,
        active: current_page?(development_path) || controller_path.start_with?("development")
      }
    end

    items
  end
end
