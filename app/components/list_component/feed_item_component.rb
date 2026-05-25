class ListComponent::FeedItemComponent < ViewComponent::Base
  DEFAULT_ITEM_CLASS = "flex items-baseline gap-3 px-4 py-3"
  CONTENT_WRAPPER_CLASSES = "flex flex-1 flex-col gap-2"
  TITLE_ROW_CLASSES = "flex flex-wrap items-center gap-2"
  TITLE_CLASSES = "inline-flex items-center text-base font-semibold text-slate-900 transition hover:text-slate-700 rounded-sm outline-none focus-visible:ring-2 focus-visible:ring-sky-500 focus-visible:ring-offset-2 focus-visible:ring-offset-white"
  METADATA_CLASSES = "flex flex-wrap items-center gap-x-2 gap-y-1 text-slate-500"
  BULLET_CLASSES = "text-slate-300"
  ACTIONS_ROW_CLASSES = "flex flex-wrap items-center gap-2 pt-1"

  def initialize(title:, title_url:, metadata_segments: [], badge: nil, actions: nil, key: nil)
    @title = title
    @title_url = title_url
    @metadata_segments = metadata_segments
    @badge = badge
    @actions = actions
    @key = key
  end

  def call
    content_tag :li, class: DEFAULT_ITEM_CLASS, data: { key: @key } do
      content_wrapper
    end
  end

  private

  def content_wrapper
    content_tag(:div, class: CONTENT_WRAPPER_CLASSES) do
      safe_join([title_row, metadata_div, actions_row].compact)
    end
  end

  def actions_row
    return nil if @actions.blank?

    content_tag(:div, @actions, class: ACTIONS_ROW_CLASSES)
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
end
