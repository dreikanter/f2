require "test_helper"

module SortableTestControllers
  class DemoController < ActionController::Base
    include Sortable

    def index
      @presenter = sortable_presenter
      render json: presenter_payload(@presenter)
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
          direction: :desc
        }
      }
    end

    def sortable_path(sort_params)
      query = sort_params.to_query
      "/sortable_test_demo_index#{query.present? ? "?#{query}" : ""}"
    end

    def presenter_payload(presenter)
      {
        current_title: presenter.current_title,
        current_direction: presenter.current_direction,
        options: presenter.options.map do |option|
          {
            field: option.field,
            title: option.title,
            active: option.active?,
            active_direction: option.active_direction
          }
        end
      }
    end
  end
end

class SortableTest < ActionDispatch::IntegrationTest
  test "#sortable_presenter should use defaults when no params provided" do
    with_sortable_routes do
      get "/sortable_test_demo_index"

      response_data = response.parsed_body
      assert_equal "Name", response_data["current_title"]
      assert_equal "asc", response_data["current_direction"]

      option = response_data["options"].detect { |item| item["active"] }
      assert_equal "name", option["field"]
      assert_equal "asc", option["active_direction"]
    end
  end

  test "#sortable_presenter should respect sort params" do
    with_sortable_routes do
      get "/sortable_test_demo_index", params: { sort: "created_at", direction: "desc" }

      response_data = response.parsed_body

      assert_equal "Created", response_data["current_title"]
      assert_equal "desc", response_data["current_direction"]

      active_option = response_data["options"].detect { |item| item["active"] }

      assert_equal "created_at", active_option["field"]
      assert_equal "desc", active_option["active_direction"]

      name_option = response_data["options"].detect { |item| item["field"] == "name" }

      assert_not name_option["active"]
    end
  end

  test "#sortable_presenter should fall back on invalid direction" do
    with_sortable_routes do
      get "/sortable_test_demo_index", params: { sort: "created_at", direction: "sideways" }

      response_data = response.parsed_body

      assert_equal "Created", response_data["current_title"]
      assert_equal "desc", response_data["current_direction"]

      active_option = response_data["options"].detect { |item| item["active"] }

      assert_equal "created_at", active_option["field"]
      assert_equal "desc", active_option["active_direction"]
    end
  end

  private

  def with_sortable_routes
    with_routing do |set|
      set.draw do
        get "/sortable_test_demo_index", to: "sortable_test_controllers/demo#index"
      end

      yield
    end
  end
end
