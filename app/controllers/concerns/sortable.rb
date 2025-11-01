module Sortable
  extend ActiveSupport::Concern

  included do
    helper_method :sortable_presenter if respond_to?(:helper_method)
  end

  private

  def sortable_presenter
    SortablePresenter.new(
      params: params,
      fields: sortable_fields,
      path_builder: ->(sortable_params) { sortable_path(sortable_params) }
    )
  end

  def sortable_field
    field = params[:sort]

    if field.present? && sortable_fields.key?(field.to_sym)
      field
    else
      sortable_default_field
    end
  end

  def sortable_default_field
    sortable_fields.keys.first.to_s
  end

  def sortable_direction
    direction = params[:direction]

    case direction
    when "asc", "desc"
      direction
    else
      default_direction_for(sortable_field)
    end
  end

  def default_direction_for(field)
    config = sortable_fields[field.to_sym]
    config ? config.fetch(:direction, "desc").to_s : "desc"
  end

  def sortable_order
    field_sql = sortable_fields.dig(sortable_field.to_sym, :order_by)
    arel_field = Arel.sql(field_sql)
    sortable_direction == "asc" ? arel_field.asc : arel_field.desc
  end

  def sortable_fields
    raise NotImplementedError, "Include Sortable and override #sortable_fields in the controller"
  end

  def sortable_path(_params)
    raise NotImplementedError, "Include Sortable and override #sortable_path(params) in the controller"
  end
end
