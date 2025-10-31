require "test_helper"
require "uri"

class PostSortPresenterTest < ActiveSupport::TestCase
  class StubController
    attr_reader :params

    def initialize(params = {})
      @params = ActionController::Parameters.new(params)
    end

    def default_sort_column
      "published"
    end

    def default_sort_direction
      "desc"
    end

    def posts_path(params)
      "/posts?#{params.to_query}"
    end
  end

  test "should expose current label and icon" do
    presenter = PostSortPresenter.new(controller: StubController.new)

    assert_equal "Published", presenter.current_label
    assert_equal "arrow-down-short", presenter.icon_name_for_button
  end

  test "should highlight active option" do
    presenter = PostSortPresenter.new(controller: StubController.new(sort: "feed", direction: "asc", feed_id: 1))

    option = presenter.options.find(&:active?)
    assert_equal "feed", option.column
    assert_equal "asc", option.active_direction
    assert_equal "arrow-up-short", option.icon_name
    uri = URI(option.path)
    assert_equal "/posts", uri.path
    params = Rack::Utils.parse_query(uri.query)
    assert_equal({ "feed_id" => "1", "sort" => "feed", "direction" => "desc" }, params)
  end

  test "should fall back to defaults for invalid params" do
    presenter = PostSortPresenter.new(controller: StubController.new(sort: "invalid", direction: "sideways"))

    assert_equal "Published", presenter.current_label
    assert_equal "desc", presenter.current_direction
  end
end
