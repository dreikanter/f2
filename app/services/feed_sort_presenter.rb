# TBD: Generalize after the use cases are clear
class FeedSortPresenter
  Option = Struct.new(:label, :column, :path, :active, :active_direction, :icon_name, keyword_init: true) do
    def active?
      active
    end
  end

  # TBD: Parameterize
  SORT_OPTIONS = {
    "Name" => "name",
    "Status" => "status",
    "Target Group" => "target_group",
    "Last Refresh" => "last_refresh",
    "Recent Post" => "recent_post"
  }.freeze

  def initialize(controller:)
    @controller = controller
  end

  def options
    @options ||= build_options
  end

  def current_label
    current_option.label
  end

  def current_direction
    case direction
    when "asc", "desc"
      direction
    else
      default_sort_direction
    end
  end

  def icon_name_for_button
    icon_for(current_direction)
  end

  private

  attr_reader :controller

  delegate :params, :default_sort_direction, to: :controller, private: true

  def current_option
    options.find(&:active?) || options.first
  end

  def resolve_sort
    SORT_OPTIONS.value?(sort) ? sort : controller.default_sort_column
  end

  def build_options
    SORT_OPTIONS.map do |label, column|
      active = resolve_sort == column
      active_direction = active ? current_direction : nil
      next_direction = active ? opposite_direction : default_sort_direction

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

  def opposite_direction
    current_direction == "asc" ? "desc" : "asc"
  end

  def icon_for(direction)
    direction == "asc" ? "arrow-up-short" : "arrow-down-short"
  end

  def direction
    @direction ||= params[:direction]
  end

  def sort
    @sort ||= params[:sort]
  end
end
