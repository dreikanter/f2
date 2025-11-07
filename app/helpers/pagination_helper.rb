module PaginationHelper
  def render_pagination(&path_helper)
    # Wrap the path helper to pass pagination params and current request params
    wrapped_path_helper = lambda do |page|
      pagination = { page: page }

      # Include common pagination params (sort, direction) if present
      pagination[:sort] = params[:sort] if params[:sort].present?
      pagination[:direction] = params[:direction] if params[:direction].present?

      path_helper.call(pagination, params)
    end

    render PaginationComponent.new(
      collection_name: controller_name,
      path_helper: wrapped_path_helper,
      current_page: pagination_current_page,
      total_pages: pagination_total_pages
    )
  end
end
