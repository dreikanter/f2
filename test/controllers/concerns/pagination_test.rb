require "test_helper"

class PaginationTest < ActionController::TestCase
  class TestController < ActionController::Base
    include Pagination

    def index
      # Test action that would use pagination
    end

    private

    def params
      @params ||= ActionController::Parameters.new(page: "2")
    end
  end

  tests TestController

  test "#pagination_scope should raise NotImplementedError when not overridden" do
    controller = TestController.new

    assert_raises(NotImplementedError) do
      controller.send(:pagination_scope)
    end
  end

  test "#pagination_current_page should return page from params" do
    controller = TestController.new

    assert_equal 2, controller.send(:pagination_current_page)
  end

  test "#pagination_current_page should default to 1 when no page param" do
    controller = TestController.new
    controller.instance_variable_set(:@params, ActionController::Parameters.new)

    assert_equal 1, controller.send(:pagination_current_page)
  end

  test "#pagination_per_page should return default value" do
    controller = TestController.new

    assert_equal 25, controller.send(:pagination_per_page)
  end

  test "#paginate_scope should raise error when pagination_scope not implemented" do
    controller = TestController.new

    assert_raises(NotImplementedError) do
      controller.send(:paginate_scope)
    end
  end
end
