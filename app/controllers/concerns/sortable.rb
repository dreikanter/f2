module Sortable
  extend ActiveSupport::Concern

  included do
    helper_method :sort_presenter if respond_to?(:helper_method)
  end

  private

  def sort_presenter
    default_field = sortable_default_field

    SortPresenter.new(
      controller: self,
      fields: sortable_presenter_fields,
      default_field: default_field,
      default_direction: default_direction_for(default_field),
      path_builder: ->(sortable_params) { sortable_path(sortable_params) },
      field_default_directions: sortable_field_default_directions
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

  def sortable_default_field
    sortable_field_definitions.first.fetch(:name)
  end

  def sortable_path(_params)
    raise NotImplementedError, "Include Sortable and override #sortable_path(params) in the controller"
  end

  def sortable_field_definitions
    @sortable_field_definitions ||= Array(sortable_fields).map { |definition| normalize_sortable_field(definition) }
  end

  def sortable_fields_map
    @sortable_fields_map ||= sortable_field_definitions.each_with_object({}) do |definition, config|
      config[definition.fetch(:name)] = definition.fetch(:order_by)
    end
  end

  def sortable_presenter_fields
    @sortable_presenter_fields ||= sortable_field_definitions.to_h do |definition|
      [definition.fetch(:title), definition.fetch(:name)]
    end
  end

  def sortable_field_default_directions
    @sortable_field_default_directions ||= sortable_field_definitions.to_h do |definition|
      [definition.fetch(:name), definition.fetch(:direction)]
    end
  end

  def default_direction_for(field)
    sortable_field_default_directions.fetch(field.to_s, "desc")
  end

  def toggle_sort_direction(direction)
    direction == "asc" ? "desc" : "asc"
  end

  def normalize_sortable_field(definition)
    hash = definition.is_a?(Hash) ? definition : definition.to_h
    hash = hash.symbolize_keys

    name = hash[:name] || hash[:column] || hash[:key]
    raise ArgumentError, "sortable field definition requires :name" if name.blank?

    order_by = hash[:order_by] || hash[:order]
    raise ArgumentError, "sortable field definition requires :order_by" if order_by.blank?

    title = hash[:title] || hash[:label] || name.to_s.titleize
    direction = (hash[:direction] || "desc").to_s

    unless %w[asc desc].include?(direction)
      raise ArgumentError, "sortable field definition direction must be :asc or :desc"
    end

    {
      name: name.to_s,
      order_by: order_by,
      title: title,
      direction: direction
    }
  end
end
