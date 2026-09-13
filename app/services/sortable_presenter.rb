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

  # @param current_sort_field [String] resolved sort field
  # @param current_direction [String] resolved sort direction
  # @param fields [Hash{Symbol=>Hash}] controller sort configuration
  # @param path_builder [Proc] callable returning a URL for the given params
  def initialize(current_sort_field:, current_direction:, fields:, path_builder:)
    @current_sort_field = current_sort_field
    @current_direction = current_direction
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

  # @return [String] resolved sort direction, "asc" or "desc"
  attr_reader :current_direction

  private

  attr_reader :current_sort_field, :fields, :path_builder

  # Option hash corresponding to the current sort selection.
  #
  # @return [Option, nil]
  def current_option
    options.find(&:active?)
  end

  def build_options
    fields.map do |field, config|
      key = field.to_s
      default_direction = config.fetch(:direction, :desc)
      active = current_sort_field == key
      active_direction = active ? current_direction : nil
      next_direction = active ? toggle_direction(current_direction) : default_direction

      Option.new(
        title: config.fetch(:title).to_s,
        field: key,
        path: path_builder.call(sort: key, direction: next_direction),
        active: active,
        active_direction: active_direction,
        icon_name: active_direction ? icon_for(active_direction) : nil
      )
    end
  end

  # @param direction [String]
  # @return [String]
  def toggle_direction(direction)
    direction == "asc" ? "desc" : "asc"
  end

  # @param direction [String]
  # @return [String]
  def icon_for(direction)
    direction == "asc" ? "arrow-up" : "arrow-down"
  end
end
