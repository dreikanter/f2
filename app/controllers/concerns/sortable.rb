module Sortable
  extend ActiveSupport::Concern

  included do
    helper_method :sort_presenter if respond_to?(:helper_method)
  end

  private

  def sort_presenter(extra_query_params = {})
    extra_query_params = extra_query_params.to_h
    SortPresenter.new(
      controller: self,
      columns: sortable_presenter_columns,
      default_column: resolved_sortable_default_column,
      default_direction: resolved_sortable_default_direction,
      path_builder: ->(sortable_params) { sortable_path(sortable_params.merge(extra_query_params)) }
    )
  end

  def sort_column
    column = params[:sort].presence || resolved_sortable_default_column
    sortable_columns_map.key?(column) ? column : resolved_sortable_default_column
  end

  def sort_direction
    direction = params[:direction].presence || resolved_sortable_default_direction
    %w[asc desc].include?(direction) ? direction : resolved_sortable_default_direction
  end

  def sort_order
    column_sql = sortable_columns_map.fetch(sort_column)
    arel_column = Arel.sql(column_sql)

    sort_direction == "asc" ? arel_column.asc : arel_column.desc
  end

  def next_sort_direction(column)
    column = column.to_s
    if sort_column == column
      toggle_sort_direction(sort_direction)
    else
      resolved_sortable_default_direction
    end
  end

  def sortable_columns
    raise NotImplementedError, "Include Sortable and override #sortable_columns in the controller"
  end

  def sortable_default_column
    sortable_column_definitions.first.fetch(:name)
  end

  def sortable_default_direction
    :desc
  end

  def sortable_path(_params)
    raise NotImplementedError, "Include Sortable and override #sortable_path(params) in the controller"
  end

  def sortable_column_definitions
    @sortable_column_definitions ||= Array(sortable_columns).map { |definition| normalize_sortable_column(definition) }
  end

  def sortable_columns_map
    @sortable_columns_map ||= sortable_column_definitions.each_with_object({}) do |definition, config|
      config[definition.fetch(:name)] = definition.fetch(:order_by)
    end
  end

  def sortable_presenter_columns
    @sortable_presenter_columns ||= sortable_column_definitions.to_h do |definition|
      [definition.fetch(:title), definition.fetch(:name)]
    end
  end

  def resolved_sortable_default_column
    @resolved_sortable_default_column ||= begin
      value = sortable_default_column.to_s
      unless sortable_columns_map.key?(value)
        raise ArgumentError, "sortable_default_column must be defined in #sortable_columns"
      end
      value
    end
  end

  def resolved_sortable_default_direction
    @resolved_sortable_default_direction ||= sortable_default_direction.to_s
  end

  def toggle_sort_direction(direction)
    direction == "asc" ? "desc" : "asc"
  end

  def normalize_sortable_column(definition)
    hash = definition.is_a?(Hash) ? definition : definition.to_h
    hash = hash.symbolize_keys

    name = hash[:name] || hash[:column] || hash[:key]
    raise ArgumentError, "sortable column definition requires :name" if name.blank?

    order_by = hash[:order_by] || hash[:order]
    raise ArgumentError, "sortable column definition requires :order_by" if order_by.blank?

    title = hash[:title] || hash[:label] || name.to_s.titleize

    { name: name.to_s, order_by: order_by, title: title }
  end
end
