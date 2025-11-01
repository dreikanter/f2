# Lightweight presenter responsible for describing the available sort options
# (labels, directions, links) for controllers including the `Sortable` concern.
#
# @see Sortable
class SortablePresenter
  # Immutable value object representing a single sort option.
  #
  # @!attribute title
  #   @return [String] human-friendly label for the option
  # @!attribute field
  #   @return [String] field identifier transmitted via params
  # @!attribute path
  #   @return [String] URL that activates the option
  # @!attribute active
  #   @return [Boolean] whether the option is currently selected
  # @!attribute active_direction
  #   @return [String, nil] current direction when active
  # @!attribute icon_name
  #   @return [String, nil] icon identifier matching the active direction
  Option = Struct.new(:title, :field, :path, :active, :active_direction, :icon_name) do
    def active?
      active
    end
  end

  # @param params [ActionController::Parameters, Hash] current request params
  # @param fields [Hash{Symbol=>Hash}] controller sort configuration
  # @param path_builder [Proc] callable returning a URL for the given params
  def initialize(params:, fields:, path_builder:)
    @params = params
    @fields = fields
    @path_builder = path_builder
  end

  # Lazily builds the available sort options.
  #
  # @return [Array<Option>]
  def options
    @options ||= build_options
  end

  # Title of the currently selected option.
  #
  # @return [String, nil]
  def current_title
    current_option&.title
  end

  # @return [String] "asc" or "desc"
  def current_direction
    @current_direction ||= begin
      value = params[:direction].presence
      %w[asc desc].include?(value) ? value : default_direction_for(current_sort_field)
    end
  end

  def icon_name_for_button
    icon_for(current_direction)
  end

  private

  attr_reader :params, :fields, :path_builder

  # @return [Option, nil] option corresponding to the current sort selection
  def current_option
    options.find(&:active?) || options.first
  end

  # Determine which field should be used for ordering.
  #
  # @return [String]
  def current_sort_field
    value = params[:sort]
    field_config_for(value) ? value : default_field
  end

  def build_options
    fields.map do |field, config|
      key = field.to_s
      title = config.fetch(:title).to_s
      default_direction = config.fetch(:direction, :desc)
      active = current_sort_field == key
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

  # @param field [String, Symbol]
  # @return [String] default direction for the provided field
  def default_direction_for(field)
    config = field_config_for(field)
    config ? config.fetch(:direction, "desc").to_s : "desc"
  end

  # @return [String] canonical default field name
  def default_field
    @default_field ||= fields.keys.first ? fields.keys.first.to_s : ""
  end

  # @param direction [String]
  # @return [String]
  def toggle_direction(direction)
    direction == "asc" ? "desc" : "asc"
  end

  # @param direction [String]
  # @return [String]
  def icon_for(direction)
    direction == "asc" ? "arrow-up-short" : "arrow-down-short"
  end

  # Looks up the configuration hash for a given field.
  #
  # @param field [String, Symbol, nil]
  # @return [Hash, nil]
  def field_config_for(field)
    return nil if field.blank?

    fields[field.to_sym]
  end
end
