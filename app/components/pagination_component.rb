class PaginationComponent < ViewComponent::Base
  attr_reader :current_page, :total_pages

  def initialize(collection_name:, path_helper:, current_page:, total_pages:)
    @collection_name = collection_name
    @path_helper = path_helper
    @current_page = current_page
    @total_pages = total_pages
  end

  def render?
    total_pages > 1
  end

  def label
    @collection_name.humanize
  end

  def path_for(page)
    @path_helper.call(page)
  end

  def each_page(window: 2)
    return enum_for(:each_page, window: window) unless block_given?

    page_start = [current_page - window, 1].max
    page_end = [page_start + (window * 2), total_pages].min
    page_start = [page_end - (window * 2), 1].max if page_end - page_start < (window * 2)

    (page_start..page_end).each { |page| yield page }
  end
end
