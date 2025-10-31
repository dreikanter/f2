module Sortable
  extend ActiveSupport::Concern

  included do
    helper_method :sort_presenter if respond_to?(:helper_method)
  end

  private

  def sort_presenter
    presenter_fields = sortable_field_definitions.map do |definition|
      {
        label: definition.fetch(:title),
        field: definition.fetch(:field).to_s,
        direction: normalize_direction(definition.fetch(:direction, "desc"))
      }
    end

    SortPresenter.new(
      controller: self,
      fields: presenter_fields,
      path_builder: ->(sortable_params) { sortable_path(sortable_params) }
    )
  end

  def sort_field
    field = params[:sort].presence || sortable_default_field
    field = field.to_s
    sortable_fields_map.key?(field) ? field : sortable_default_field
  end

  def sort_direction
    direction = params[:direction].presence
    return direction if %w[asc desc].include?(direction)

    default_direction_for(sort_field)
  end

  def sort_order
    field_sql = sortable_fields_map.fetch(sort_field)
    arel_field = Arel.sql(field_sql)

    sort_direction == "asc" ? arel_field.asc : arel_field.desc
  end

  def next_sort_direction(field)
    field = field.to_s
    if sort_field == field
      toggle_sort_direction(sort_direction)
    else
      default_direction_for(field)
    end
  end

  def sortable_fields
    raise NotImplementedError, "Include Sortable and override #sortable_fields in the controller"
  end

  def sortable_path(_params)
    raise NotImplementedError, "Include Sortable and override #sortable_path(params) in the controller"
  end

  def sortable_default_field
    definition = sortable_field_definitions.first
    definition ? definition.fetch(:field).to_s : ""
  end

  def sortable_field_definitions
    @sortable_field_definitions ||= Array(sortable_fields)
  end

  def sortable_field_definitions_map
    @sortable_field_definitions_map ||= sortable_field_definitions.each_with_object({}) do |definition, map|
      map[definition.fetch(:field).to_s] = definition
    end
  end

  def sortable_fields_map
    @sortable_fields_map ||= sortable_field_definitions_map.transform_values { |definition| definition.fetch(:order_by) }
  end

  def default_direction_for(field)
    definition = sortable_field_definitions_map[field.to_s]
    normalize_direction(definition ? definition.fetch(:direction, "desc") : "desc")
  end

  def toggle_sort_direction(direction)
    direction == "asc" ? "desc" : "asc"
  end

  def normalize_direction(direction)
    value = direction.to_s
    %w[asc desc].include?(value) ? value : "desc"
  end
end
