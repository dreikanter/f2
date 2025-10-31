require "test_helper"

class FeedSortPresenterTest < ActiveSupport::TestCase
  class StubController
    attr_reader :params

    def initialize(params = {})
      @params = ActionController::Parameters.new(params)
    end

    def default_sort_column
      "name"
    end

    def default_sort_direction
      "asc"
    end

    def feeds_path(sort:, direction:)
      "/feeds?sort=#{sort}&direction=#{direction}"
    end
  end

  test "button caption reflects current sort and direction" do
    presenter = FeedSortPresenter.new(controller: StubController.new)

    assert_equal "Name", presenter.button_caption
  end

  test "options include information for each sort column" do
    presenter = FeedSortPresenter.new(controller: StubController.new(sort: "status", direction: "desc"))

    option = presenter.options.detect(&:active?)
    assert option
    assert_equal "status", option.column
    assert_equal "desc", option.active_direction
    assert_equal "arrow-down-short", option.icon_name
    assert_equal "/feeds?sort=status&direction=asc", option.path
  end

  test "invalid params fall back to defaults" do
    presenter = FeedSortPresenter.new(controller: StubController.new(sort: "invalid", direction: "sideways"))

    assert_equal "Name", presenter.current_label
    assert_equal "asc", presenter.current_direction
  end
end
