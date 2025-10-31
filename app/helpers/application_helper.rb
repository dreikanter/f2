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

  def icon(name, css_class: nil, title: nil, aria_hidden: nil, aria_label: nil)
    options = { class: class_names("bi", "bi-#{name}", css_class) }
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

  def sortable_header(column:, title:, path_params: {})
    default_sort_column = controller.respond_to?(:sortable_default_column, true) ? controller.send(:sortable_default_column).to_s : nil

    current_sort = if controller.respond_to?(:sort_column, true)
      controller.send(:sort_column)
    else
      params[:sort].presence || default_sort_column
    end

    current_direction = if controller.respond_to?(:sort_direction, true)
      controller.send(:sort_direction)
    else
      default_direction_for_current = if controller.respond_to?(:default_direction_for, true)
        controller.send(:default_direction_for, current_sort || default_sort_column)
      else
        "desc"
      end
      params[:direction].presence || default_direction_for_current
    end

    default_direction_for_column = if controller.respond_to?(:default_direction_for, true)
      controller.send(:default_direction_for, column)
    else
      "desc"
    end

    direction = current_sort == column ? current_direction : nil

    next_direction = if current_sort == column
      current_direction == "asc" ? "desc" : "asc"
    else
      default_direction_for_column
    end

    link_to title, path_params.merge(sort: column, direction: next_direction),
            class: class_names("sortable", "sorted-#{direction}": direction.present?),
            data: { turbo_action: "replace" }
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
