module PaginationHelper
  def each_page(current_page, total_pages, window: 2)
    return enum_for(:each_page, current_page, total_pages, window: window) unless block_given?

    page_start = [current_page - window, 1].max
    page_end = [page_start + (window * 2), total_pages].min
    page_start = [page_end - (window * 2), 1].max if page_end - page_start < (window * 2)

    (page_start..page_end).each { |page| yield page }
  end

  def pagination_for(collection, collection_name:, path_helper:, **options)
    locals = {
      pagination_label: collection_name.humanize,
      pagination_path: path_helper
    }

    # Use provided pagination values or attempt to call helper methods from controller
    locals[:pagination_current_page] = options.delete(:pagination_current_page) ||
                                        (respond_to?(:pagination_current_page) ? pagination_current_page : 1)
    locals[:pagination_total_pages] = options.delete(:pagination_total_pages) ||
                                      (respond_to?(:pagination_total_pages) ? pagination_total_pages : 1)

    render "shared/pagination", **locals, **options
  end
end
