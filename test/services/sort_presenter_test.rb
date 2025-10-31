require "test_helper"
require "rack/utils"

class SortPresenterTest < ActiveSupport::TestCase
  class StubController
    attr_reader :params

    def initialize(params = {})
      @params = ActionController::Parameters.new(params)
    end
  end

  test "uses defaults when params are missing" do
    controller = StubController.new
    presenter = SortPresenter.new(
      controller: controller,
      columns: { "Name" => "name" },
      default_column: :name,
      default_direction: :asc,
      path_builder: ->(params) { "/items?#{params.to_query}" }
    )

    assert_equal "Name", presenter.current_label
    assert_equal "asc", presenter.current_direction
    assert_equal "arrow-up-short", presenter.icon_name_for_button

    option = presenter.options.first
    assert option.active?
    assert_equal({ "sort" => "name", "direction" => "desc" }, query_params(option.path))
  end

  test "honors provided params and toggles direction" do
    controller = StubController.new(sort: "status", direction: "desc", extra: "1")
    columns = { "Name" => "name", "Status" => "status" }

    presenter = SortPresenter.new(
      controller: controller,
      columns: columns,
      default_column: :name,
      default_direction: :asc,
      path_builder: ->(params) { "/items?#{params.merge(extra: controller.params[:extra]).to_query}" }
    )

    active_option = presenter.options.detect(&:active?)
    assert_equal "status", active_option.column
    assert_equal "desc", active_option.active_direction
    assert_equal "arrow-down-short", active_option.icon_name
    assert_equal(
      { "extra" => "1", "sort" => "status", "direction" => "asc" },
      query_params(active_option.path)
    )
  end

  test "falls back to defaults for invalid params" do
    controller = StubController.new(sort: "invalid", direction: "sideways")
    presenter = SortPresenter.new(
      controller: controller,
      columns: { "Name" => "name" },
      default_column: :name,
      default_direction: :asc,
      path_builder: ->(params) { "/items?#{params.to_query}" }
    )

    assert_equal "Name", presenter.current_label
    assert_equal "asc", presenter.current_direction
  end

  private

  def query_params(path)
    Rack::Utils.parse_query(path.split("?").last)
  end
end
