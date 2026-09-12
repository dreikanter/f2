require "test_helper"
require "rack/utils"

class SortablePresenterTest < ActiveSupport::TestCase
  test "#options should show the resolved selection and toggle ascending order" do
    presenter = SortablePresenter.new(
      current_sort_field: "name",
      current_direction: "asc",
      fields: {
        name: {
          title: "Name",
          order_by: "LOWER(items.name)",
          direction: :asc
        }
      },
      path_builder: ->(params) { "/items?#{params.to_query}" }
    )

    assert_equal "Name", presenter.current_title
    assert_equal "asc", presenter.current_direction

    option = presenter.options.first
    assert option.active?
    assert_equal "arrow-up", option.icon_name

    expected = {
      "sort" => "name",
      "direction" => "desc"
    }

    assert_equal expected, query_params(option.path)
  end

  test "#options should toggle descending order and preserve link parameters" do
    presenter = SortablePresenter.new(
      current_sort_field: "status",
      current_direction: "desc",
      fields: {
        name: {
          title: "Name",
          order_by: "LOWER(items.name)",
          direction: :asc
        },
        status: {
          title: "Status",
          order_by: "status",
          direction: :desc
        }
      },
      path_builder: ->(params) { "/items?#{params.merge(extra: "1").to_query}" }
    )

    active_option = presenter.options.detect(&:active?)

    assert_equal "status", active_option.field
    assert_equal "desc", active_option.active_direction
    assert_equal "arrow-down", active_option.icon_name

    inactive_option = presenter.options.find { |option| option.field == "name" }
    assert_not inactive_option.active?
    assert_nil inactive_option.active_direction
    assert_nil inactive_option.icon_name
    assert_equal({ "extra" => "1", "sort" => "name", "direction" => "asc" }, query_params(inactive_option.path))

    expected = {
      "extra" => "1",
      "sort" => "status",
      "direction" => "asc"
    }

    assert_equal(expected, query_params(active_option.path))
  end

  private

  def query_params(path)
    Rack::Utils.parse_query(path.split("?").last)
  end
end
