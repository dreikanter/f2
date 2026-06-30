class SortDropdownComponent < ViewComponent::Base
  include ApplicationHelper

  def initialize(presenter:, menu_id:)
    @presenter = presenter
    @menu_id = menu_id
  end

  private

  attr_reader :presenter, :menu_id

  def button_id
    "#{menu_id}-button"
  end

  def direction_icon
    presenter.current_direction == "asc" ? "arrow-up" : "arrow-down"
  end

  def direction_label
    presenter.current_direction == "asc" ? "Ascending" : "Descending"
  end

  def option_classes(option)
    helpers.class_names(
      "flex items-center justify-between gap-2 px-4 py-2 transition hover:bg-surface-muted focus:bg-surface-sunken focus:outline-none",
      "font-semibold text-heading": option.active?
    )
  end
end
