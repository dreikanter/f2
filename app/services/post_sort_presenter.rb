class PostSortPresenter
  Option = Struct.new(:label, :column, :path, :active, :active_direction, :icon_name, keyword_init: true) do
    def active?
      active
    end
  end

  SORT_OPTIONS = {
    "Published" => "published",
    "Feed" => "feed",
    "Status" => "status",
    "Attachments" => "attachments",
    "Comments" => "comments"
  }.freeze

  def initialize(controller:)
    @controller = controller
    @options = build_options
  end

  attr_reader :options

  delegate :params, to: :controller

  def current_label
    current_option.label
  end

  def current_direction
    @current_direction ||= begin
      value = params[:direction]
      %w[asc desc].include?(value) ? value : controller.default_sort_direction
    end
  end

  def icon_name_for_button
    icon_for(current_direction)
  end

  private

  attr_reader :controller

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
      next_direction = active ? toggle_direction(current_direction) : controller.default_sort_direction

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
    controller.posts_path(base_path_params.merge(sort: column, direction: direction))
  end

  def base_path_params
    @base_path_params ||= begin
      permitted = {}
      permitted[:feed_id] = params[:feed_id] if params[:feed_id].present?
      permitted
    end
  end

  def toggle_direction(direction)
    direction == "asc" ? "desc" : "asc"
  end

  def icon_for(direction)
    direction == "asc" ? "arrow-up-short" : "arrow-down-short"
  end
end
