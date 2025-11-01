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
      {
        name: {
          title: "Name",
          order_by: "LOWER(items.name)",
          direction: :asc
        },
        created_at: {
          title: "Created",
          order_by: "items.created_at",
          direction: :asc
        }
      }
    end

    def sortable_path(sort_params)
      "/items?#{sort_params.merge(filter: "all").to_query}"
    end
  end

  setup do
    @controller = TestController.new
    @controller.params = ActionController::Parameters.new
  end

  test "#sortable_field should return field from params" do
    @controller.params[:sort] = "name"

    assert_equal "name", @controller.send(:sortable_field)
  end

  test "#sortable_field should fall back when field param invalid" do
    @controller.params[:sort] = "invalid_field"

    assert_equal "name", @controller.send(:sortable_field)
  end

  test "#sortable_field should fall back when field param missing" do
    assert_equal "name", @controller.send(:sortable_field)
  end

  test "#sortable_direction should return direction from params" do
    @controller.params[:direction] = "desc"

    assert_equal "desc", @controller.send(:sortable_direction)
  end

  test "#sortable_direction should fall back when direction invalid" do
    @controller.params[:direction] = "invalid"

    assert_equal "asc", @controller.send(:sortable_direction)
  end

  test "#sortable_direction should fall back when direction missing" do
    assert_equal "asc", @controller.send(:sortable_direction)
  end

  test "#sortable_order should return ascending node" do
    @controller.params[:sort] = "name"
    @controller.params[:direction] = "asc"

    order = @controller.send(:sortable_order)
    assert_instance_of Arel::Nodes::Ascending, order
  end

  test "#sortable_order should return descending node" do
    @controller.params[:sort] = "name"
    @controller.params[:direction] = "desc"

    order = @controller.send(:sortable_order)
    assert_instance_of Arel::Nodes::Descending, order
  end

  test "#sortable_presenter should build presenter with configured path" do
    presenter = @controller.send(:sortable_presenter)
    option = presenter.options.first

    assert_equal "Name", option.title

    expected = {
      "filter" => "all",
      "sort" => "name",
      "direction" => "desc"
    }

    assert_equal expected, query_params(option.path)
  end

  private

  def query_params(path)
    Rack::Utils.parse_query(path.split("?").last)
  end
end
