class FeedSortPresenter
  Option = Struct.new(:label, :column, :path, :active, :active_direction, :icon_name, keyword_init: true) do
    def active?
      active
    end
  end

  SORT_OPTIONS = {
    "Name" => "name",
    "Status" => "status",
    "Target Group" => "target_group",
    "Last Refresh" => "last_refresh",
    "Recent Post" => "recent_post"
  }.freeze

  def initialize(controller:)
    @controller = controller
    @options = build_options
  end

  attr_reader :options, :controller

  delegate :params, :default_sort_direction, to: :controller

  def current_label
    current_option.label
  end

  def current_direction
    @current_direction ||= begin
      value = params[:direction]
      %w[asc desc].include?(value) ? value : default_sort_direction
    end
  end

  def button_caption
    current_label
  end

  def icon_name_for_button
    icon_for(current_direction)
  end

  private

  def current_option
    @options.find(&:active?) || @options.first
  end

  def resolve_sort
    value = params[:sort]
    SORT_OPTIONS.value?(value) ? value : controller.default_sort_column
  end

  def build_options
    SORT_OPTIONS.map do |label, column|
      active = resolve_sort == column
      active_direction = active ? current_direction : nil
      next_direction = active ? toggle_direction(current_direction) : default_sort_direction

      Option.new(
        label: label,
        column: column,
        path: build_path(column, next_direction),
        active: active,
        active_direction: active_direction,
        icon_name: active_direction ? icon_for(active_direction) : nil
      )
    end
  end

  def build_path(column, direction)
    controller.feeds_path(sort: column, direction: direction)
  end

  def toggle_direction(direction)
    direction == "asc" ? "desc" : "asc"
  end

  def direction_hint_for(direction)
    direction == "asc" ? "A-Z" : "Z-A"
  end

  def icon_for(direction)
    direction == "asc" ? "arrow-up-short" : "arrow-down-short"
  end
end
