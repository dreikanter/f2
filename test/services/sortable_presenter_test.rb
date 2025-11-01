require "test_helper"
require "rack/utils"

class SortablePresenterTest < ActiveSupport::TestCase
  class StubController
    attr_reader :params

    def initialize(params = {})
      @params = ActionController::Parameters.new(params)
    end
  end

  def new_presenter(controller_params: {}, fields:, path_builder:)
    controller = StubController.new(controller_params)
    SortablePresenter.new(controller: controller, fields: fields, path_builder: path_builder)
  end

  test "uses defaults when params are missing" do
    presenter = new_presenter(
      fields: {
        name: { title: "Name", order_by: "LOWER(items.name)", direction: :asc }
      },
      path_builder: ->(params) { "/items?#{params.to_query}" }
    )

    assert_equal "Name", presenter.current_label
    assert_equal "asc", presenter.current_direction

    option = presenter.options.first
    assert option.active?
    assert_equal({ "sort" => "name", "direction" => "desc" }, query_params(option.path))
  end

  test "honors provided params and toggles direction" do
    presenter = new_presenter(
      controller_params: { sort: "status", direction: "desc", extra: "1" },
      fields: {
        name: { title: "Name", order_by: "LOWER(items.name)", direction: :asc },
        status: { title: "Status", order_by: "status", direction: :desc }
      },
      path_builder: ->(params) { "/items?#{params.merge(extra: "1").to_query}" }
    )

    active_option = presenter.options.detect(&:active?)
    assert_equal "status", active_option.field
    assert_equal "desc", active_option.active_direction
    assert_equal({ "extra" => "1", "sort" => "status", "direction" => "asc" }, query_params(active_option.path))
  end

  test "falls back to defaults for invalid params" do
    presenter = new_presenter(
      controller_params: { sort: "invalid", direction: "sideways" },
      fields: {
        name: { title: "Name", order_by: "LOWER(items.name)", direction: :asc }
      },
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
