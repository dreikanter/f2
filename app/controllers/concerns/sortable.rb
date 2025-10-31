module Sortable
  extend ActiveSupport::Concern

  included do
    helper_method :sort_presenter if respond_to?(:helper_method)
  end

  private

  def sort_presenter
    SortPresenter.new(
      controller: self,
      fields: sortable_field_definitions,
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
    sortable_field_definitions.first.fetch(:field)
  end

  def sortable_field_definitions
    @sortable_field_definitions ||= sortable_fields.map { |definition| normalize_sortable_field(definition) }
  end

  def sortable_field_definitions_map
    @sortable_field_definitions_map ||= sortable_field_definitions.index_by { |definition| definition.fetch(:field) }
  end

  def sortable_fields_map
    @sortable_fields_map ||= sortable_field_definitions_map.transform_values { |definition| definition.fetch(:order_by) }
  end

  def default_direction_for(field)
    definition = sortable_field_definitions_map[field.to_s]
    definition ? definition.fetch(:direction) : "desc"
  end

  def toggle_sort_direction(direction)
    direction == "asc" ? "desc" : "asc"
  end

  def normalize_sortable_field(definition)
    hash = definition.is_a?(Hash) ? definition : definition.to_h
    hash = hash.symbolize_keys

    field = hash[:field] || hash[:name]
    raise ArgumentError, "sortable field definition requires :field" if field.blank?

    label = (hash[:title] || hash[:label])
    raise ArgumentError, "sortable field definition requires :title" if label.blank?

    order_by = hash[:order_by]
    raise ArgumentError, "sortable field definition requires :order_by" if order_by.blank?

    direction = (hash[:direction] || "desc").to_s
    unless %w[asc desc].include?(direction)
      raise ArgumentError, "sortable field definition :direction must be :asc or :desc"
    end

    {
      field: field.to_s,
      label: label.to_s,
      order_by: order_by,
      direction: direction
    }
  end
end
