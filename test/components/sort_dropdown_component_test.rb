require "test_helper"
require "view_component/test_case"

class SortDropdownComponentTest < ViewComponent::TestCase
  def presenter
    @presenter ||= SortablePresenter.new(
      params: { sort: "name", direction: "asc" },
      fields: { name: { title: "Name", direction: :asc }, created_at: { title: "Created", direction: :desc } },
      path_builder: ->(params) { "/things?#{params.to_query}" }
    )
  end

  test "#call should render the trigger button with the current sort title and direction" do
    result = render_inline(SortDropdownComponent.new(presenter: presenter, menu_id: "things-menu"))

    button = result.at_css("#things-menu-button")
    assert_not_nil button
    assert_equal "things-menu", button["data-dropdown-toggle"]
    assert_includes button.text, "Name"
    assert_includes button.text, "Ascending"
  end

  test "#call should render the menu panel with each sort option" do
    result = render_inline(SortDropdownComponent.new(presenter: presenter, menu_id: "things-menu"))

    panel = result.at_css("#things-menu")
    assert_not_nil panel
    assert_equal "menu", panel["role"]
    assert_equal "things-menu-button", panel["aria-labelledby"]
    assert_equal 2, panel.css("a").size
    titles = panel.css("a span").map(&:text)
    assert_includes titles, "Name"
    assert_includes titles, "Created"
  end

  test "#call should mark the active option with bolder styling" do
    result = render_inline(SortDropdownComponent.new(presenter: presenter, menu_id: "things-menu"))

    active_link = result.at_css("#things-menu a.font-semibold")
    assert_not_nil active_link
    assert_includes active_link.text, "Name"
  end
end
