class ListComponent::ItemComponent < ViewComponent::Base
  ITEM_CLASSES = "flex flex-wrap items-center justify-between gap-x-4 gap-y-2 px-4 py-3"
  CONTENT_CLASSES = "flex flex-1 flex-col gap-1"
  TITLE_ROW_CLASSES = "flex flex-wrap items-center gap-2"
  TITLE_CLASSES = "inline-flex items-center text-base font-semibold text-slate-900 transition hover:text-slate-700 rounded-sm outline-none focus-visible:ring-2 focus-visible:ring-sky-500 focus-visible:ring-offset-2 focus-visible:ring-offset-white"
  METADATA_CLASSES = "flex flex-wrap items-center gap-x-2 gap-y-1 text-sm text-slate-500"
  BULLET_CLASSES = "text-slate-300"
  ACTIONS_CLASSES = "flex items-center gap-2 shrink-0"

  def initialize(title:, title_url:, metadata_segments: [], badge: nil, actions: nil, note: nil, key: nil)
    @title = title
    @title_url = title_url
    @metadata_segments = metadata_segments
    @badge = badge
    @actions = actions
    @note = note
    @key = key
  end

  def call
    content_tag :li, class: ITEM_CLASSES, data: key_data do
      safe_join([content_div, actions_div].compact)
    end
  end

  private

  def content_div
    content_tag(:div, class: CONTENT_CLASSES) do
      safe_join([title_row, metadata_div, @note].compact)
    end
  end

  def actions_div
    return if @actions.blank?

    content_tag(:div, @actions, class: ACTIONS_CLASSES)
  end

  def title_row
    content_tag(:div, class: TITLE_ROW_CLASSES) do
      safe_join([title_link, @badge].compact)
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

  def key_data
    @key ? { key: @key } : {}
  end
end
