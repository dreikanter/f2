require "test_helper"
require "view_component/test_case"

class LinkedCardComponentTest < ViewComponent::TestCase
  test "#call should render a linked title, icon, and description" do
    result = render_inline(LinkedCardComponent.new(
      href:        "/settings",
      title:       "Settings",
      icon:        "user",
      description: "Manage your account",
      class:       "custom-card",
      data:        { key: "settings.card" }
    ))

    card = result.at_css("a[data-key='settings.card']")
    assert_not_nil card
    assert_equal "/settings", card["href"]
    assert_equal "Settings", card.at_css("h2").text.strip
    assert_equal "Manage your account", card.at_css("p").text
    assert_equal 1, card.css("svg").size
    assert_includes card["class"], "custom-card"
    assert_includes card["class"], "bg-surface"
    assert_includes card["class"], "p-6"
    assert_includes card["class"], "no-underline"
    assert_includes card["class"], "shadow-xs"
    assert_includes card["class"], "hover:shadow-md"
    assert_includes card["class"], "hover:bg-surface-muted"
  end

  test "#call should indicate links opening in a new tab" do
    result = render_inline(LinkedCardComponent.new(
      href:        "/jobs",
      title:       "Background Jobs",
      icon:        "hard-hat",
      description: "Monitor job queues",
      target:      "_blank",
      rel:         "noopener noreferrer"
    ))

    card = result.at_css("a")
    assert_not_nil card
    assert_equal "_blank", card["target"]
    assert_equal "noopener noreferrer", card["rel"]
    assert_equal 2, card.css("svg").size
  end

  test "#call should render disabled cards without a link" do
    result = render_inline(LinkedCardComponent.new(
      href:        "/emails",
      title:       "Sent Emails",
      icon:        "inbox",
      description: "Review captured emails",
      disabled:    true,
      tooltip:     "Email capture is not configured",
      target:      "_blank",
      rel:         "noopener"
    ))

    assert_empty result.css("a")
    card = result.at_css("[aria-disabled='true']")
    assert_not_nil card
    assert_equal "link", card["role"]
    assert_equal "Sent Emails", card.at_css("h2").text.strip
    assert_equal "Review captured emails", card.at_css("p").text
    assert_equal "Email capture is not configured", card["title"]
    assert_nil card["href"]
    assert_nil card["target"]
    assert_nil card["rel"]
    assert_equal 1, card.css("svg").size
    assert_includes card["class"], "opacity-50"
    assert_includes card["class"], "cursor-not-allowed"
    refute_includes card["class"], "hover:"
  end

  test "#call should escape title and description text" do
    result = render_inline(LinkedCardComponent.new(
      href:        "/settings",
      title:       "<em>Settings</em>",
      icon:        "user",
      description: "<script>alert('test')</script>"
    ))

    assert_equal "<em>Settings</em>", result.at_css("h2").text.strip
    assert_equal "<script>alert('test')</script>", result.at_css("p").text
    assert_empty result.css("em, script")
  end
end
