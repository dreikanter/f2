module Sortable
  extend ActiveSupport::Concern

  private

  # @return [SortablePresenter] sort controls presenter
  def sortable_presenter
    SortablePresenter.new(
      params: params,
      fields: sortable_fields,
      path_builder: ->(sortable_params) { sortable_path(sortable_params) }
    )
  end

  # @return [String] selected or default sort field
  def sortable_field
    field = params[:sort]

    if field.present? && sortable_fields.key?(field.to_s.to_sym)
      field
    else
      sortable_default_field
    end
  end

  # @return [String] first configured sort field
  def sortable_default_field
    sortable_fields.keys.first.to_s
  end

  # @return [String] either "asc" or "desc"
  def sortable_direction
    direction = params[:direction]

    case direction
    when "asc", "desc"
      direction
    else
      default_direction_for(sortable_field)
    end
  end

  # @param field [String, Symbol] sort field
  # @return [String] either "asc" or "desc"
  def default_direction_for(field)
    config = sortable_fields[field.to_sym]
    config ? config.fetch(:direction, "desc").to_s : "desc"
  end

  # @return [Arel::Nodes::Ordering] ordering with the configured NULL placement
  def sortable_order
    field_name = sortable_field.to_sym
    config = sortable_fields.fetch(field_name, {})
    field_sql = config[:order_by]

    if field_sql.blank?
      raise ArgumentError, "Sortable field #{field_name.inspect} must define :order_by SQL"
    end

    arel_field = Arel.sql(field_sql)
    ordering = sortable_direction == "asc" ? arel_field.asc : arel_field.desc
    config[:nulls] == :last ? ordering.nulls_last : ordering
  end

  # @return [Hash{Symbol=>Hash}] sort field configuration
  def sortable_fields
    raise NotImplementedError, "Include Sortable and override #sortable_fields in the controller"
  end

  # @param _params [Hash] sort query parameters
  # @return [String] path with sort parameters
  def sortable_path(_params)
    raise NotImplementedError, "Include Sortable and override #sortable_path(params) in the controller"
  end
end
