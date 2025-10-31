class SortPresenter
  Option = Struct.new(:label, :column, :path, :active, :active_direction, :icon_name, keyword_init: true) do
    def active?
      active
    end
  end

  def initialize(controller:, columns:, default_column:, default_direction:, path_builder:, base_params: {})
    @controller = controller
    @columns = columns
    @default_column = default_column.to_s
    @default_direction = default_direction.to_s
    @path_builder = path_builder
    @base_params = base_params.symbolize_keys
  end

  def options
    @options ||= build_options
  end

  def current_label
    current_option.label
  end

  def current_direction
    @current_direction ||= begin
      value = params[:direction].presence
      %w[asc desc].include?(value) ? value : default_direction
    end
  end

  def icon_name_for_button
    icon_for(current_direction)
  end

  private

  attr_reader :controller, :columns, :default_column, :default_direction, :path_builder, :base_params

  delegate :params, to: :controller

  def current_option
    options.find(&:active?) || options.first
  end

  def resolved_sort
    value = params[:sort].presence
    columns.value?(value) ? value : default_column
  end

  def build_options
    columns.map do |label, column|
      active = resolved_sort == column
      active_direction = active ? current_direction : nil
      next_direction = active ? toggle_direction(current_direction) : default_direction

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
    path_builder.call(base_params.merge(sort: column, direction: direction))
  end

  def toggle_direction(direction)
    direction == "asc" ? "desc" : "asc"
  end

  def icon_for(direction)
    direction == "asc" ? "arrow-up-short" : "arrow-down-short"
  end
end
