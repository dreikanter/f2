require "test_helper"
require "rack/utils"

class SortablePresenterTest < ActiveSupport::TestCase
  class StubController
    attr_reader :params

    def initialize(params = {})
      @params = ActionController::Parameters.new(params)
    end
  end

  test "#options should use defaults when params are missing" do
    presenter = SortablePresenter.new(
      params: {},
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
    assert_equal({ "sort" => "name", "direction" => "desc" }, query_params(option.path))
  end

  test "#options should honor provided params and toggle direction" do
    presenter = SortablePresenter.new(
      params: { sort: "status", direction: "desc", extra: "1" },
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

    expected = {
      "extra" => "1",
      "sort" => "status",
      "direction" => "asc"
    }

    assert_equal(expected, query_params(active_option.path))
  end

  test "#current_direction should fall back to defaults for invalid params" do
    presenter = SortablePresenter.new(
      params: { sort: "invalid", direction: "sideways" },
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
  end

  private

  def query_params(path)
    Rack::Utils.parse_query(path.split("?").last)
  end
end
