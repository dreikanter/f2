module Pagination
  extend ActiveSupport::Concern

  DEFAULT_PER_PAGE = 25
  MAX_PER_PAGE = 100

  included do
    helper_method :pagination_total_pages, :pagination_current_page, :pagination_per_page, :pagination_total_count
  end

  private

  def paginate_scope
    pagination_scope.limit(pagination_per_page).offset(pagination_offset)
  end

  def pagination_offset
    (pagination_current_page - 1) * pagination_per_page
  end

  def pagination_current_page
    @pagination_current_page ||= [params[:page].to_i, 1].max
  end

  def pagination_total_count
    @pagination_total_count ||= pagination_scope.unscope(:select, :order).count
  end

  def pagination_total_pages
    @pagination_total_pages ||= (pagination_total_count.to_f / pagination_per_page).ceil
  end

  def pagination_per_page
    @pagination_per_page ||= begin
      requested = params[:per_page].to_i
      requested = DEFAULT_PER_PAGE unless requested.positive?
      [requested, MAX_PER_PAGE].min
    end
  end

  # Override this method in the including controller to provide the scope to paginate
  def pagination_scope
    raise NotImplementedError, "Controllers using Pagination must implement pagination_scope method"
  end
end
