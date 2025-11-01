class ListGroupComponent::PostItemComponent < ViewComponent::Base
  DEFAULT_ITEM_CLASS = "flex flex-col gap-2 p-4 sm:flex-row sm:items-start sm:gap-4"
  CONTENT_WRAPPER_CLASSES = "flex items-start gap-3 sm:flex-1"
  ICON_CLASSES = "inline-flex shrink-0 text-slate-500"
  INNER_WRAPPER_CLASSES = "flex flex-1 flex-col gap-1"
  TITLE_CLASSES = "inline-flex items-start text-base font-semibold text-slate-900 transition hover:text-slate-700 ff-focus-ring"
  METADATA_CLASSES = "ff-text flex flex-wrap items-center gap-x-2 gap-y-1 text-sm text-slate-500"
  BULLET_CLASSES = "text-slate-300"

  def initialize(icon:, title:, title_url:, metadata_segments: [], key: nil)
    @icon = icon
    @title = title
    @title_url = title_url
    @metadata_segments = metadata_segments
    @key = key
  end

  def call
    content_tag :li, class: DEFAULT_ITEM_CLASS, data: { key: @key } do
      content_tag(:div, class: CONTENT_WRAPPER_CLASSES) do
        safe_join([icon_span, inner_wrapper])
      end
    end
  end

  private

  def icon_span
    content_tag(:span, @icon, class: ICON_CLASSES)
  end

  def inner_wrapper
    content_tag(:div, class: INNER_WRAPPER_CLASSES) do
      safe_join([title_link, metadata_div])
    end
  end

  def title_link
    @title_url ? link_to(@title, @title_url, class: TITLE_CLASSES) : content_tag(:span, @title, class: TITLE_CLASSES)
  end

  def metadata_div
    return if @metadata_segments.empty?

    content_tag(:div, class: METADATA_CLASSES) do
      segments = @metadata_segments.flat_map.with_index do |segment, index|
        parts = []
        parts << content_tag(:span, "&bull;".html_safe, "aria-hidden": true, class: BULLET_CLASSES) if index.positive?
        parts << content_tag(:span, segment)
        parts
      end
      safe_join(segments)
    end
  end
end
