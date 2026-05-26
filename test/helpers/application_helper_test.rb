require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  attr_accessor :policy_override

  PolicyStub = Struct.new(:allowed) do
    def index?
      allowed
    end
  end

  def policy(record)
    (policy_override || ->(_record) { PolicyStub.new(false) }).call(record)
  end

  teardown do
    Current.session = nil
    self.policy_override = nil
  end

  test "#page_header without block renders title with simple layout" do
    result = page_header("Test Title")

    expected = <<~HTML.strip
      <div class="d-flex justify-content-between align-items-center mb-4"><h1>Test Title</h1></div>
    HTML

    assert_equal expected, result
  end

  test "#page_header with block renders title and content with flex layout" do
    result = page_header("Test Title") do
      content_tag(:a, "Link", href: "/test", class: "btn btn-primary")
    end

    expected = <<~HTML.strip
      <div class="d-flex justify-content-between align-items-center mb-4"><h1>Test Title</h1><a href="/test" class="btn btn-primary">Link</a></div>
    HTML

    assert_equal expected, result
  end

  test "#page_header with text block content" do
    result = page_header("Settings") do
      "Some content"
    end

    expected = <<~HTML.strip
      <div class="d-flex justify-content-between align-items-center mb-4"><h1>Settings</h1>Some content</div>
    HTML

    assert_equal expected, result
  end

  test "#page_section_header renders h2 with title and classes" do
    result = page_section_header("Title")

    expected = '<h2 class="mt-5 mb-4">Title</h2>'

    assert_equal expected, result
  end

  test "#page_section_header accepts custom class argument" do
    result = page_section_header("Title", class: "text-primary")

    expected = '<h2 class="mt-5 mb-4 text-primary">Title</h2>'

    assert_equal expected, result
  end

  test "#page_header accepts custom class argument" do
    result = page_header("Test Title", class: "border-bottom")

    expected = <<~HTML.strip
      <div class="d-flex justify-content-between align-items-center mb-4 border-bottom"><h1>Test Title</h1></div>
    HTML

    assert_equal expected, result
  end


  test "#post_content_preview returns empty string for nil content" do
    assert_equal "", post_content_preview(nil)
  end

  test "#post_content_preview returns empty string for blank content" do
    assert_equal "", post_content_preview("")
    assert_equal "", post_content_preview("   ")
  end

  test "#post_content_preview truncates long content" do
    long_content = "a" * 200
    result = post_content_preview(long_content)
    assert result.length < 200
    assert result.end_with?("...")
  end

  test "#post_content_preview returns content as-is when short" do
    short_content = "Short content"
    assert_equal short_content, post_content_preview(short_content)
  end

  test "#post_content_preview strips whitespace" do
    content_with_whitespace = "  Content with spaces  "
    assert_equal "Content with spaces", post_content_preview(content_with_whitespace)
  end

  test "#lucide_icon returns svg for known icon" do
    result = lucide_icon("star")
    assert_includes result, "<svg"
    assert_includes result, 'aria-hidden="true"'
    assert_includes result, 'class="shrink-0"'
  end

  test "#lucide_icon returns svg with css class" do
    result = lucide_icon("star", css_class: "size-4 text-warning")
    assert_includes result, 'class="shrink-0 size-4 text-warning"'
  end

  test "#lucide_icon returns empty string for unknown icon" do
    result = lucide_icon("nonexistent-icon")
    assert_equal "", result
  end

  test "#lucide_icon renders title attribute when provided" do
    result = lucide_icon("star", title: "Favorite")
    assert_includes result, 'title="Favorite"'
    assert_includes result, 'aria-hidden="true"'
  end

  test "#lucide_icon renders aria-label and role when aria_label provided" do
    result = lucide_icon("star", aria_label: "Favorite")
    assert_includes result, 'aria-label="Favorite"'
    assert_includes result, 'role="img"'
    assert_not_includes result, "aria-hidden"
  end

  test "#post_status_icon returns draft icon for draft status" do
    result = post_status_icon("draft")
    assert_includes result, "<svg"
    assert_includes result, 'title="Draft"'
    assert_includes result, "text-muted"
  end

  test "#post_status_icon returns enqueued icon for enqueued status" do
    result = post_status_icon("enqueued")
    assert_includes result, "<svg"
    assert_includes result, 'title="Enqueued"'
    assert_includes result, "text-secondary"
  end

  test "#post_status_icon returns rejected icon for rejected status" do
    result = post_status_icon("rejected")
    assert_includes result, "<svg"
    assert_includes result, 'title="Rejected"'
    assert_includes result, "text-danger"
  end

  test "#post_status_icon returns published icon for published status" do
    result = post_status_icon("published")
    assert_includes result, "<svg"
    assert_includes result, 'title="Published"'
    assert_includes result, "text-success"
  end

  test "#post_status_icon returns failed icon for failed status" do
    result = post_status_icon("failed")
    assert_includes result, "<svg"
    assert_includes result, 'title="Failed"'
    assert_includes result, "text-danger"
  end

  test "#post_status_icon returns withdrawn icon for withdrawn status" do
    result = post_status_icon("withdrawn")
    assert_includes result, "<svg"
    assert_includes result, 'title="Withdrawn"'
    assert_includes result, "text-secondary"
  end

  test "#post_status_icon returns capitalized text for unknown status" do
    result = post_status_icon("unknown")
    expected = '<span class="text-muted">Unknown</span>'
    assert_equal expected, result
  end

  test "#highlight_json wraps output in highlight div" do
    json_hash = { "test" => "value" }
    result = highlight_json(json_hash)

    assert_includes result, "<div class=\"highlight\">"
    assert_includes result, "</div>"
  end

  test "#navbar_items should return empty array when user is missing" do
    assert_equal [], navbar_items
  end

  test "#navbar_items should return only status for inactive user" do
    user = create(:user, :inactive)
    Current.session = create(:session, user: user)

    current_page_stub = ->(_path, *_args) { false }

    self.stub(:current_page?, current_page_stub) do
      self.stub(:controller_path, "dashboard") do
        items = navbar_items

        assert_equal 1, items.size
        assert_equal "Status", items.first[:name]
        assert_equal status_path, items.first[:path]
        assert_equal false, items.first[:active]
      end
    end
  end

  test "#navbar_items should include feeds and posts for active user" do
    user = create(:user)
    Current.session = create(:session, user: user)

    current_page_stub = ->(path, *_args) { path == feeds_path }

    self.stub(:current_page?, current_page_stub) do
      self.stub(:controller_path, "feeds/index") do
        items = navbar_items

        assert_equal ["Status", "Feeds", "Posts"], items.map { |item| item[:name] }
        feeds_item = items.second
        assert_equal feeds_path, feeds_item[:path]
        assert_equal true, feeds_item[:active]
      end
    end
  end

  test "#navbar_items should include admin panel when allowed" do
    user = create(:user)
    Current.session = create(:session, user: user)

    current_page_stub = ->(path, *_args) { path == admin_path }

    self.stub(:current_page?, current_page_stub) do
      self.stub(:controller_path, "admin/dashboard") do
        self.policy_override = ->(_record) { PolicyStub.new(true) }

        items = navbar_items
        admin_item = items.last

        assert_equal "Admin Panel", admin_item[:name]
        assert_equal admin_path, admin_item[:path]
        assert_equal true, admin_item[:active]
      end
    end
  end
end
