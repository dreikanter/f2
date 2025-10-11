require "test_helper"

class SortableTest < ActionDispatch::IntegrationTest
  class TestController < ApplicationController
    include Sortable

    sortable_by({
      "name" => "LOWER(items.name)",
      "created_at" => "items.created_at"
    }, default_column: :name, default_direction: :asc)

    def index
      render plain: "OK"
    end
  end

  setup do
    @controller = TestController.new
    @controller.params = ActionController::Parameters.new
  end

  test "next_sort_direction returns desc when sorting by same column ascending" do
    @controller.params[:sort] = "name"
    @controller.params[:direction] = "asc"

    assert_equal "desc", @controller.send(:next_sort_direction, "name")
  end

  test "next_sort_direction returns asc when sorting by same column descending" do
    @controller.params[:sort] = "name"
    @controller.params[:direction] = "desc"

    assert_equal "asc", @controller.send(:next_sort_direction, "name")
  end

  test "next_sort_direction returns default direction when sorting by different column" do
    @controller.params[:sort] = "name"
    @controller.params[:direction] = "desc"

    assert_equal "asc", @controller.send(:next_sort_direction, "created_at")
  end

  test "next_sort_direction toggles direction when no sort params but checking default column" do
    # When no params, sort_column returns default "name" and sort_direction returns default "asc"
    # So next_sort_direction("name") compares "name" == "name" and toggles "asc" to "desc"
    assert_equal "desc", @controller.send(:next_sort_direction, "name")
  end

  test "next_sort_direction returns default direction when no sort params and different column" do
    # When no params, sort_column returns default "name"
    # So next_sort_direction("created_at") compares "created_at" == "name" (false) and returns default "asc"
    assert_equal "asc", @controller.send(:next_sort_direction, "created_at")
  end

  test "sort_column returns valid column from params" do
    @controller.params[:sort] = "name"

    assert_equal "name", @controller.send(:sort_column)
  end

  test "sort_column returns default when invalid column in params" do
    @controller.params[:sort] = "invalid_column"

    assert_equal "name", @controller.send(:sort_column)
  end

  test "sort_column returns default when no params" do
    assert_equal "name", @controller.send(:sort_column)
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
end
