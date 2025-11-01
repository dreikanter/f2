class SortablePresenter
  Option = Struct.new(:title, :field, :path, :active, :active_direction, :icon_name, keyword_init: true) do
    def active?
      active
    end
  end

  def initialize(controller:, fields:, path_builder:)
    @controller = controller
    @fields = fields
    @path_builder = path_builder
  end

  def options
    @options ||= build_options
  end

  def current_title
    current_option&.title
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
    field_config_for(value) ? value : default_field
  end

  def build_options
    fields.map do |field, config|
      key = field.to_s
      title = config.fetch(:title).to_s
      default_direction = normalize_direction(config.fetch(:direction, :desc))
      active = resolved_sort == key
      active_direction = active ? current_direction : nil
      next_direction = active ? toggle_direction(current_direction) : default_direction

      Option.new(
        title: title,
        field: key,
        path: path_builder.call(sort: key, direction: next_direction),
        active: active,
        active_direction: active_direction,
        icon_name: active_direction ? icon_for(active_direction) : nil
      )
    end
  end

  def default_direction_for(field_value)
    config = field_config_for(field_value)
    normalize_direction(config ? config.fetch(:direction, :desc) : :desc)
  end

  def default_field
    @default_field ||= fields.keys.first ? fields.keys.first.to_s : ""
  end

  def toggle_direction(direction)
    direction == "asc" ? "desc" : "asc"
  end

  def icon_for(direction)
    direction == "asc" ? "arrow-up-short" : "arrow-down-short"
  end

  def normalize_direction(direction)
    value = direction.to_s
    %w[asc desc].include?(value) ? value : "desc"
  end

  def field_config_for(field)
    return nil if field.blank?

    fields[field.to_sym] || fields[field.to_s]
  end
end
