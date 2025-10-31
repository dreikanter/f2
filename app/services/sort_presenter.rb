class SortPresenter
  Option = Struct.new(:label, :field, :path, :active, :active_direction, :icon_name, keyword_init: true) do
    def active?
      active
    end
  end

  def initialize(controller:, fields:, path_builder:)
    @controller = controller
    @fields = normalize_fields(fields)
    @path_builder = path_builder
  end

  def options
    @options ||= build_options
  end

  def current_label
    current_option&.label
  end

  def current_direction
    @current_direction ||= begin
      value = params[:direction].presence
      %w[asc desc].include?(value) ? value : default_direction_for(resolved_sort)
    end
  end

  def icon_name_for_button
    icon_for(current_direction)
  end

  private

  attr_reader :controller, :fields, :path_builder

  delegate :params, to: :controller

  def current_option
    options.find(&:active?) || options.first
  end

  def resolved_sort
    value = params[:sort].presence
    fields_by_key.key?(value) ? value : default_field
  end

  def build_options
    fields.map do |field|
      name = field[:field]
      active = resolved_sort == name
      active_direction = active ? current_direction : nil
      default_direction = field[:direction]
      next_direction = active ? toggle_direction(current_direction) : default_direction

      Option.new(
        label: field[:label],
        field: name,
        path: path_builder.call(sort: name, direction: next_direction),
        active: active,
        active_direction: active_direction,
        icon_name: active_direction ? icon_for(active_direction) : nil
      )
    end
  end

  def default_direction_for(field_value)
    field = fields_by_key[field_value]
    field ? field[:direction] : "desc"
  end

  def default_field
    @default_field ||= fields.first ? fields.first[:field] : ""
  end

  def fields_by_key
    @fields_by_key ||= fields.each_with_object({}) do |field, map|
      map[field[:field]] = field
    end
  end

  def toggle_direction(direction)
    direction == "asc" ? "desc" : "asc"
  end

  def icon_for(direction)
    direction == "asc" ? "arrow-up-short" : "arrow-down-short"
  end

  def normalize_fields(fields)
    Array(fields).map do |field|
      field = field.respond_to?(:symbolize_keys) ? field.symbolize_keys : field.to_h.symbolize_keys

      label = field.fetch(:label).to_s
      name = field.fetch(:field).to_s
      direction = normalize_direction(field.fetch(:direction, "desc"))

      {
        label: label,
        field: name,
        direction: direction
      }
    end
  end

  def normalize_direction(direction)
    direction = direction.to_s
    %w[asc desc].include?(direction) ? direction : "desc"
  end
end
