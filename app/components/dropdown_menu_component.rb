# An ellipsis "more options" button that toggles a dropdown of actions. Shared
# by the feed and post list rows and their page headers, which differ in their
# items and in the trigger's `variant` (see TRIGGER_CLASSES).
#
# Each item is a hash; nils are dropped so callers can build the list with inline
# conditionals. Items with a `method` render as button_to forms (e.g. enable /
# disable); the rest render as links. Supported keys:
#
#   { label:, href:, method:, params:, target:, rel:, data: }
class DropdownMenuComponent < ViewComponent::Base
  ITEM_CLASS = "block px-4 py-2 text-sm text-slate-700 transition hover:bg-slate-50"

  # The trigger is a square, icon-only button. In list rows and cards it stays a
  # subtle borderless ellipsis; in a page header it matches the bordered action
  # buttons (Enable, Refresh) it sits beside — same height, border, and chrome.
  TRIGGER_CLASSES = {
    row: "inline-flex size-7 items-center justify-center rounded text-slate-400 transition " \
      "hover:bg-slate-100 hover:text-slate-600 focus:outline-none focus-visible:ring-2 focus-visible:ring-sky-500",
    header: "inline-flex items-center justify-center rounded-md border border-slate-200 bg-white p-3 " \
      "text-slate-600 shadow-sm transition hover:bg-slate-50 focus:outline-none focus:ring-2 focus:ring-sky-500 " \
      "focus:ring-offset-1 cursor-pointer"
  }.freeze

  def initialize(menu_id:, items:, width: "w-44", label: "More options", variant: :row)
    @menu_id = menu_id
    @items = items.compact
    @width = width
    @label = label
    @variant = variant
  end

  private

  attr_reader :menu_id, :items, :width, :label

  def trigger_class
    TRIGGER_CLASSES.fetch(@variant)
  end

  def render_item(item)
    if item[:method]
      helpers.button_to(item[:label], item[:href],
                        method: item[:method],
                        params: item[:params],
                        class: "#{ITEM_CLASS} w-full text-left",
                        role: "menuitem",
                        data: item[:data],
                        form: { class: "block" })
    else
      helpers.link_to(item[:label], item[:href],
                      class: ITEM_CLASS,
                      role: "menuitem",
                      target: item[:target],
                      rel: item[:rel],
                      data: item[:data])
    end
  end
end
