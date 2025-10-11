module Pagination
  extend ActiveSupport::Concern

  included do
    helper_method :pagination_total_pages, :pagination_current_page, :pagination_per_page, :pagination_total_count
  end

  private

  def paginate_scope(scope = nil)
    scope ||= pagination_scope
    scope.limit(pagination_per_page).offset(pagination_offset)
  end

  def pagination_offset(page = pagination_current_page)
    (page - 1) * pagination_per_page
  end

  def pagination_current_page
    @pagination_current_page ||= (params[:page] || 1).to_i
  end

  def pagination_total_count
    @pagination_total_count ||= pagination_scope.count
  end

  def pagination_total_pages
    @pagination_total_pages ||= (pagination_total_count.to_f / pagination_per_page).ceil
  end

  def pagination_per_page
    params[:per_page]&.to_i || 25
  end

  # Override this method in the including controller to provide the scope to paginate
  def pagination_scope
    raise NotImplementedError, "Controllers using Pagination must implement pagination_scope method"
  end
end
