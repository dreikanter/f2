module PaginationHelper
  def each_page(current_page, total_pages, window: 2)
    return enum_for(:each_page, current_page, total_pages, window: window) unless block_given?

    page_start = [current_page - window, 1].max
    page_end = [page_start + (window * 2), total_pages].min
    page_start = [page_end - (window * 2), 1].max if page_end - page_start < (window * 2)

    (page_start..page_end).each { |page| yield page }
  end

  def pagination_for(collection, collection_name:, path_helper:, template: "shared/pagination", **options)
    render template,
           pagination_label: collection_name.humanize,
           pagination_path: path_helper,
           collection_size: collection.size,
           collection_name: collection_name,
           **options
  end
end
