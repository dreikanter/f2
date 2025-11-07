require "test_helper"

class PaginationHelperTest < ActionView::TestCase
  test "#each_page should yield correct page range for beginning pages" do
    pages = []
    each_page(1, 10) { |page| pages << page }

    assert_equal [1, 2, 3, 4, 5], pages
  end

  test "#each_page should yield correct page range for middle pages" do
    pages = []
    each_page(5, 10) { |page| pages << page }

    assert_equal [3, 4, 5, 6, 7], pages
  end

  test "#each_page should yield correct page range for end pages" do
    pages = []
    each_page(10, 10) { |page| pages << page }

    assert_equal [6, 7, 8, 9, 10], pages
  end

  test "#each_page should handle small total page counts" do
    pages = []
    each_page(2, 3) { |page| pages << page }

    assert_equal [1, 2, 3], pages
  end

  test "#each_page should handle single page" do
    pages = []
    each_page(1, 1) { |page| pages << page }

    assert_equal [1], pages
  end

  test "#each_page should return enumerator when no block given" do
    result = each_page(5, 10)

    assert_instance_of Enumerator, result
    assert_equal [3, 4, 5, 6, 7], result.to_a
  end

  test "#each_page should respect custom window size" do
    pages = []
    each_page(5, 20, window: 3) { |page| pages << page }

    assert_equal [2, 3, 4, 5, 6, 7, 8], pages
  end

  test "#pagination_for should call render with correct parameters" do
    collection = [1, 2, 3]
    path_helper = ->(page) { "/test?page=#{page}" }

    # Test that the method calls render with the expected parameters
    actual_params = nil
    render_stub = lambda do |partial, options|
      actual_params = { partial: partial }.merge(options)
      "<div>pagination</div>"
    end

    self.stub :render, render_stub do
      result = pagination_for(collection, collection_name: "events", path_helper: path_helper)

      assert_equal "<div>pagination</div>", result
      assert_equal "shared/pagination", actual_params[:partial]
      assert_equal "Events", actual_params[:pagination_label]
      assert_equal path_helper, actual_params[:pagination_path]
      assert_equal 1, actual_params[:pagination_current_page]
      assert_equal 1, actual_params[:pagination_total_pages]
    end
  end

  test "#pagination_for should humanize collection name for label" do
    collection = [1, 2, 3]
    path_helper = ->(page) { "/test?page=#{page}" }

    actual_params = nil
    render_stub = lambda do |partial, options|
      actual_params = { partial: partial }.merge(options)
      "<div>pagination</div>"
    end

    self.stub :render, render_stub do
      result = pagination_for(collection, collection_name: "feed_items", path_helper: path_helper)

      assert_equal "<div>pagination</div>", result
      assert_equal "Feed items", actual_params[:pagination_label]
    end
  end

  test "#pagination_for should pass through additional options" do
    collection = [1, 2, 3]
    path_helper = ->(page) { "/test?page=#{page}" }

    actual_params = nil
    render_stub = lambda do |partial, options|
      actual_params = { partial: partial }.merge(options)
      "<div>pagination</div>"
    end

    self.stub :render, render_stub do
      result = pagination_for(collection, collection_name: "events", path_helper: path_helper, custom_option: "value")

      assert_equal "<div>pagination</div>", result
      assert_equal "value", actual_params[:custom_option]
    end
  end
end
