class ListGroupComponent::AccessTokenItemComponent < ViewComponent::Base
  include ApplicationHelper
  include TimeHelper

  DEFAULT_ITEM_CLASS = "flex items-baseline gap-3 p-4"
  ICON_CLASSES = "inline-flex shrink-0 text-slate-500"
  CONTENT_WRAPPER_CLASSES = "flex flex-1 flex-col gap-1"
  TITLE_CLASSES = "inline-flex items-center gap-2 text-base font-semibold text-slate-900"
  LINK_CLASSES = "transition hover:text-slate-700 ff-focus-ring"
  METADATA_CLASSES = "ff-text flex flex-wrap items-center gap-x-2 gap-y-1 text-slate-500"
  BULLET_CLASSES = "text-slate-300"

  def initialize(access_token:, key: nil)
    @access_token = access_token
    @key = key
  end

  def call
    content_tag :li, class: DEFAULT_ITEM_CLASS, data: { key: @key } do
      safe_join([icon_span, content_wrapper])
    end
  end

  private

  def icon_span
    content_tag(:span, status_icon, class: ICON_CLASSES)
  end

  def status_icon
    case @access_token.status
    when "active"
      icon("check-circle", css_class: "h-5 w-5 text-emerald-600", aria_label: "Active")
    when "inactive"
      icon("x-circle", css_class: "h-5 w-5 text-slate-400", aria_label: "Inactive")
    when "pending", "validating"
      icon("clock", css_class: "h-5 w-5 text-slate-400", aria_label: @access_token.status.capitalize)
    end
  end

  def content_wrapper
    content_tag(:div, class: CONTENT_WRAPPER_CLASSES) do
      safe_join([title_line, metadata_div])
    end
  end

  def title_line
    content_tag(:div, class: TITLE_CLASSES) do
      safe_join([
        link_to(username_with_host, settings_access_token_path(@access_token), class: LINK_CLASSES),
        content_tag(:span, @access_token.name)
      ], " ")
    end
  end

  def username_with_host
    owner = @access_token.owner.presence || "—"
    host = URI.parse(@access_token.host).host
    "#{owner}@#{host}"
  end

  def metadata_div
    content_tag(:div, class: METADATA_CLASSES) do
      segments = [
        "Created: #{short_time_ago(@access_token.created_at)}",
        last_used_segment
      ].compact

      parts = segments.flat_map.with_index do |segment, index|
        result = []
        result << content_tag(:span, "&bull;".html_safe, "aria-hidden": true, class: BULLET_CLASSES) if index.positive?
        result << content_tag(:span, segment)
        result
      end

      safe_join(parts)
    end
  end

  def last_used_segment
    if @access_token.last_used_at
      "Last used: #{short_time_ago(@access_token.last_used_at)}"
    else
      "Last used: Never"
    end
  end
end
