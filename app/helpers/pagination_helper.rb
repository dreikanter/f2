module PaginationHelper
  def pagination(path_helper)
    render PaginationComponent.new(
      collection_name: controller_name,
      path_helper: path_helper,
      current_page: pagination_current_page,
      total_pages: pagination_total_pages
    )
  end
end
