require "test_helper"
require "view_component/test_case"

class PaginationComponentTest < ViewComponent::TestCase
  test "#each_page should yield correct page range for beginning pages" do
    component = create_component(current_page: 1, total_pages: 10)
    pages = []
    component.each_page { |page| pages << page }

    assert_equal [1, 2, 3, 4, 5], pages
  end

  test "#each_page should yield correct page range for middle pages" do
    component = create_component(current_page: 5, total_pages: 10)
    pages = []
    component.each_page { |page| pages << page }

    assert_equal [3, 4, 5, 6, 7], pages
  end

  test "#each_page should yield correct page range for end pages" do
    component = create_component(current_page: 10, total_pages: 10)
    pages = []
    component.each_page { |page| pages << page }

    assert_equal [6, 7, 8, 9, 10], pages
  end

  test "#each_page should handle small total page counts" do
    component = create_component(current_page: 2, total_pages: 3)
    pages = []
    component.each_page { |page| pages << page }

    assert_equal [1, 2, 3], pages
  end

  test "#each_page should handle single page" do
    component = create_component(current_page: 1, total_pages: 1)
    pages = []
    component.each_page { |page| pages << page }

    assert_equal [1], pages
  end

  test "#each_page should return enumerator when no block given" do
    component = create_component(current_page: 5, total_pages: 10)
    result = component.each_page

    assert_instance_of Enumerator, result
    assert_equal [3, 4, 5, 6, 7], result.to_a
  end

  test "#each_page should respect custom window size" do
    component = create_component(current_page: 5, total_pages: 20)
    pages = []
    component.each_page(window: 3) { |page| pages << page }

    assert_equal [2, 3, 4, 5, 6, 7, 8], pages
  end

  test "should render pagination with correct structure" do
    path_helper = ->(page) { "/test?page=#{page}" }

    result = render_inline(PaginationComponent.new(
      collection_name: "events",
      path_helper: path_helper,
      current_page: 2,
      total_pages: 5
    ))

    nav = result.at_css("nav[aria-label='Events pagination']")
    assert_not_nil nav
    assert_not_nil result.at_css("a[href='/test?page=1']")
    assert_includes result.css("a").map(&:text), "Previous"
    assert_not_nil result.at_css("a[href='/test?page=3']")
    assert_includes result.css("a").map(&:text), "Next"
    assert_includes result.css("span").map(&:text), "2"
  end

  test "should humanize collection name for label" do
    path_helper = ->(page) { "/test?page=#{page}" }

    result = render_inline(PaginationComponent.new(
      collection_name: "feed_items",
      path_helper: path_helper,
      current_page: 1,
      total_pages: 2
    ))

    nav = result.at_css("nav[aria-label='Feed items pagination']")
    assert_not_nil nav
  end

  test "should not render when total pages is 1" do
    path_helper = ->(page) { "/test?page=#{page}" }

    result = render_inline(PaginationComponent.new(
      collection_name: "events",
      path_helper: path_helper,
      current_page: 1,
      total_pages: 1
    ))

    assert_nil result.at_css("nav")
  end

  test "should disable Previous link on first page" do
    path_helper = ->(page) { "/test?page=#{page}" }

    result = render_inline(PaginationComponent.new(
      collection_name: "events",
      path_helper: path_helper,
      current_page: 1,
      total_pages: 3
    ))

    previous_links = result.css("a").select { |a| a.text == "Previous" }
    assert_equal 0, previous_links.size
    assert_includes result.css("span").map(&:text), "Previous"
  end

  test "should disable Next link on last page" do
    path_helper = ->(page) { "/test?page=#{page}" }

    result = render_inline(PaginationComponent.new(
      collection_name: "events",
      path_helper: path_helper,
      current_page: 3,
      total_pages: 3
    ))

    next_links = result.css("a").select { |a| a.text == "Next" }
    assert_equal 0, next_links.size
    assert_includes result.css("span").map(&:text), "Next"
  end

  private

  def create_component(current_page:, total_pages:)
    PaginationComponent.new(
      collection_name: "items",
      path_helper: ->(page) { "/test?page=#{page}" },
      current_page: current_page,
      total_pages: total_pages
    )
  end
end
