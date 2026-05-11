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

  def trigger_classes
    "inline-flex items-center justify-center whitespace-nowrap rounded-md " \
      "border border-slate-200 bg-white px-4 py-2 text-base font-semibold text-slate-600 " \
      "shadow-sm transition hover:bg-slate-50 " \
      "focus:outline-none focus:ring-2 focus:ring-sky-500 focus:ring-offset-1 gap-2"
  end

  def panel_classes
    "z-20 hidden w-60 rounded-lg border border-slate-200 bg-white shadow-sm"
  end

  def option_classes(option)
    helpers.class_names(
      "flex items-center justify-between gap-2 px-4 py-2 transition hover:bg-slate-50 focus:bg-slate-100 focus:outline-none",
      "font-semibold text-slate-900": option.active?
    )
  end
end
