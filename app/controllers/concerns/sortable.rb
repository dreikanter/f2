module Sortable
  extend ActiveSupport::Concern

  included do
    class_attribute :sortable_columns_config
    class_attribute :default_sort_column
    class_attribute :default_sort_direction
  end

  class_methods do
    def sortable_by(columns, default_column:, default_direction: :desc)
      self.sortable_columns_config = columns.stringify_keys
      self.default_sort_column = default_column.to_s
      self.default_sort_direction = default_direction.to_s
    end
  end

  private

  def sort_column
    column = params[:sort].presence || default_sort_column
    sortable_columns_config.key?(column) ? column : default_sort_column
  end

  def sort_direction
    direction = params[:direction].presence || default_sort_direction
    %w[asc desc].include?(direction) ? direction : default_sort_direction
  end

  def sort_order
    Arel.sql("#{sortable_columns_config[sort_column]} #{sort_direction}")
  end

  def next_sort_direction(column)
    if sort_column == column
      sort_direction == "asc" ? "desc" : "asc"
    else
      default_sort_direction
    end
  end
end
