require "test_helper"
require "rack/utils"

class SortableTest < ActionDispatch::IntegrationTest
  class TestController < ApplicationController
    include Sortable

    def index
      render plain: "OK"
    end

    private

    def sortable_fields
      [
        { field: :name, title: "Name", order_by: "LOWER(items.name)", direction: :asc },
        { field: :created_at, title: "Created", order_by: "items.created_at", direction: :asc }
      ]
    end

    def sortable_path(sort_params)
      "/items?#{sort_params.merge(filter: "all").to_query}"
    end
  end

  setup do
    @controller = TestController.new
    @controller.params = ActionController::Parameters.new
  end

  test "sort_field returns valid field from params" do
    @controller.params[:sort] = "name"

    assert_equal "name", @controller.send(:sort_field)
  end

  test "sort_field returns default when invalid field in params" do
    @controller.params[:sort] = "invalid_field"

    assert_equal "name", @controller.send(:sort_field)
  end

  test "sort_field returns default when no params" do
    assert_equal "name", @controller.send(:sort_field)
  end

  test "sort_direction returns valid direction from params" do
    @controller.params[:direction] = "desc"

    assert_equal "desc", @controller.send(:sort_direction)
  end

  test "sort_direction returns default when invalid direction in params" do
    @controller.params[:direction] = "invalid"

    assert_equal "asc", @controller.send(:sort_direction)
  end

  test "sort_direction returns default when no params" do
    assert_equal "asc", @controller.send(:sort_direction)
  end

  test "sort_order returns Arel ascending node" do
    @controller.params[:sort] = "name"
    @controller.params[:direction] = "asc"

    order = @controller.send(:sort_order)
    assert_instance_of Arel::Nodes::Ascending, order
  end

  test "sort_order returns Arel descending node" do
    @controller.params[:sort] = "name"
    @controller.params[:direction] = "desc"

    order = @controller.send(:sort_order)
    assert_instance_of Arel::Nodes::Descending, order
  end

  test "sort_presenter builds presenter with configured path and base params" do
    presenter = @controller.send(:sort_presenter)
    option = presenter.options.first

    assert_equal "Name", option.label
    assert_equal(
      { "filter" => "all", "sort" => "name", "direction" => "desc" },
      query_params(option.path)
    )
  end

  private

  def query_params(path)
    Rack::Utils.parse_query(path.split("?").last)
  end
end
