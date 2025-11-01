module Sortable
  extend ActiveSupport::Concern

  included do
    helper_method :sortable_presenter if respond_to?(:helper_method)
  end

  private

  # Builds the presenter that encapsulates available sort fields configuration
  # and current options.
  #
  # @return [SortablePresenter]
  def sortable_presenter
    SortablePresenter.new(
      params: params,
      fields: sortable_fields,
      path_builder: ->(sortable_params) { sortable_path(sortable_params) }
    )
  end

  # Resolves the requested sort field, falling back to the default when the
  # param is missing or invalid.
  #
  # @return [String]
  def sortable_field
    field = params[:sort]

    if field.present? && sortable_fields.key?(field.to_s.to_sym)
      field
    else
      sortable_default_field
    end
  end

  # The default sort field configured by the controller, which is the first one
  # in the sortable_fields hash.
  #
  # @return [String]
  def sortable_default_field
    sortable_fields.keys.first.to_s
  end

  # Resolves the sort direction, sanitising unexpected values.
  #
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

  # The configured default direction for a specific field.
  #
  # @param field [String, Symbol]
  # @return [String] either "asc" or "desc"
  def default_direction_for(field)
    config = sortable_fields[field.to_sym]
    config ? config.fetch(:direction, "desc").to_s : "desc"
  end

  # The Arel expression representing the current order clause. Intended
  # for use in the "index" action that outputs the ordered records.
  #
  # @return [Arel::Nodes::Ordering]
  def sortable_order
    field_name = sortable_field.to_sym
    field_sql = sortable_fields.dig(field_name, :order_by)

    if field_sql.blank?
      raise ArgumentError, "Sortable field #{field_name.inspect} must define :order_by SQL"
    end

    arel_field = Arel.sql(field_sql)
    sortable_direction == "asc" ? arel_field.asc : arel_field.desc
  end

  # Returns the configuration hash describing available sort fields.
  # Controllers including this concern must override this method.
  #
  # @return [Hash{Symbol=>Hash}]
  def sortable_fields
    raise NotImplementedError, "Include Sortable and override #sortable_fields in the controller"
  end

  # Builds the path for a specific sort configuration.
  # Controllers including this concern must override this method.
  #
  # @param params [Hash] additional query params to apply to the generated path
  # @return [String]
  def sortable_path(_params)
    raise NotImplementedError, "Include Sortable and override #sortable_path(params) in the controller"
  end
end
