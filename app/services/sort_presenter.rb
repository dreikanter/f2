class SortPresenter
  Option = Struct.new(:label, :column, :path, :active, :active_direction, :icon_name, keyword_init: true) do
    def active?
      active
    end
  end

  def initialize(controller:, columns:, default_column:, default_direction:, path_builder:, column_default_directions: {})
    @controller = controller
    @columns = columns
    @default_column = default_column.to_s
    @default_direction = default_direction.to_s
    @path_builder = path_builder
    @column_default_directions = column_default_directions.transform_keys(&:to_s).transform_values(&:to_s)
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

  attr_reader :controller, :columns, :default_column, :default_direction, :path_builder, :column_default_directions

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
      column = column.to_s
      active = resolved_sort == column
      active_direction = active ? current_direction : nil
      default_direction_for_column = column_default_directions.fetch(column, default_direction)
      next_direction = active ? toggle_direction(current_direction) : default_direction_for_column

      Option.new(
        label: label,
        column: column,
        path: path_builder.call(sort: column, direction: next_direction),
        active: active,
        active_direction: active_direction,
        icon_name: active_direction ? icon_for(active_direction) : nil
      )
    end
  end

  def toggle_direction(direction)
    direction == "asc" ? "desc" : "asc"
  end

  def icon_for(direction)
    direction == "asc" ? "arrow-up-short" : "arrow-down-short"
  end
end
