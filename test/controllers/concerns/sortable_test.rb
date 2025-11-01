require "test_helper"

module SortableTestControllers
  class DemoController < ActionController::Base
    include Sortable

    def index
      @presenter = sortable_presenter

      render inline: <<~HTML, locals: { presenter: @presenter }
        <div id="current-title"><%= presenter.current_title %></div>
        <div id="current-direction"><%= presenter.current_direction %></div>
        <ul id="sort-options">
          <% presenter.options.each do |option| %>
            <li>
              <a
                href="<%= option.path %>"
                data-field="<%= option.field %>"
                data-active="<%= option.active %>"
                data-active-direction="<%= option.active_direction %>"
              >
                <%= option.title %>
              </a>
            </li>
          <% end %>
        </ul>
      HTML
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
      "/sortable_test_demo_index?#{sort_params.to_query}"
    end
  end
end

class SortableTest < ActionDispatch::IntegrationTest
  test "#sortable_presenter should use defaults when no params provided" do
    with_sortable_routes do
      get sortable_test_demo_index_path

      assert_response :success
      assert_select "#current-title", "Name"
      assert_select "#current-direction", "asc"
      assert_select "#sort-options a[data-field='name'][data-active='true'][data-active-direction='asc']"
    end
  end

  test "#sortable_presenter should respect sort params" do
    with_sortable_routes do
      get sortable_test_demo_index_path(sort: "created_at", direction: "desc")

      assert_response :success
      assert_select "#current-title", "Created"
      assert_select "#current-direction", "desc"
      assert_select "#sort-options a[data-field='created_at'][data-active='true'][data-active-direction='desc']"
      assert_select "#sort-options a[data-field='name'][data-active='false']"
    end
  end

  test "#sortable_presenter should fall back on invalid direction" do
    with_sortable_routes do
      get sortable_test_demo_index_path(sort: "created_at", direction: "sideways")

      assert_response :success
      assert_select "#current-title", "Created"
      assert_select "#current-direction", "desc"
      assert_select "#sort-options a[data-field='created_at'][data-active='true'][data-active-direction='desc']"
    end
  end

  private

  def with_sortable_routes
    with_routing do |set|
      set.draw do
        get "/sortable_test_demo_index", to: "sortable_test_controllers/demo#index", as: :sortable_test_demo_index
      end

      yield
    end
  end
end
