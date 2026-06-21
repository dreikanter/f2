# A list row for use inside ListComponent's generic <ul>. Lays out an optional
# leading icon, a primary line, an optional second line, and an optional
# trailing element:
#
#   [icon] [primary]            [trailing]
#          [secondary]
#
# Every slot is optional. The icon is vertically centered with the primary line;
# the secondary line hangs indented (pl-7 = icon w-4 + gap-3) so it lines up
# under the primary text. The trailing element is top-aligned with the primary
# line. The component owns the layout; callers style their own slot content.
# Sized for size-4 leading icons.
class ListItemComponent < ViewComponent::Base
  renders_one :icon
  renders_one :primary
  renders_one :secondary
  renders_one :trailing

  # `id` and `data` land on the <li> (dom_id for Turbo, test/scan hooks);
  # `css_class` adds row-level styling such as background tints and hover.
  def initialize(id: nil, css_class: nil, data: {})
    @id = id
    @css_class = css_class
    @data = data
  end

  private

  def li_class
    helpers.class_names("px-5 py-3", @css_class)
  end

  # The second line only hangs under the primary text when there is a leading
  # icon to clear; without one it starts at the row's edge.
  def secondary_class
    helpers.class_names("mt-1", "pl-7" => icon?)
  end
end
