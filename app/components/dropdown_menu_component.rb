# An ellipsis "more options" button that toggles a dropdown of actions. Shared
# by the feed and post list rows, which differ only in their items.
#
# Each item is a hash; nils are dropped so callers can build the list with inline
# conditionals. Items with a `method` render as button_to forms (e.g. enable /
# disable); the rest render as links. Supported keys:
#
#   { label:, href:, method:, params:, target:, rel:, data: }
class DropdownMenuComponent < ViewComponent::Base
  ITEM_CLASS = "block px-4 py-2 text-sm text-slate-700 transition hover:bg-slate-50"

  def initialize(menu_id:, items:, width: "w-44", label: "More options")
    @menu_id = menu_id
    @items = items.compact
    @width = width
    @label = label
  end

  private

  attr_reader :menu_id, :items, :width, :label

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
