require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  attr_accessor :policy_override

  PolicyStub = Struct.new(:admin, :dev) do
    def admin?
      admin
    end

    def dev?
      dev
    end
  end

  def policy(record)
    (policy_override || ->(_record) { PolicyStub.new(false, false) }).call(record)
  end

  teardown do
    Current.session = nil
    self.policy_override = nil
  end

  test "#h1 should retain heading styles alongside caller attributes" do
    render inline: '<%= h1 "Sign in", id: "page-title", class: "break-words" %>'

    assert_select "h1#page-title.text-4xl.font-semibold.mb-6.text-heading.break-words", text: "Sign in"
  end

  test "#h2 should capture heading content and retain layout classes" do
    render inline: <<~ERB
      <%= h2 class: "flex items-center gap-2", data: { key: "settings.heading" } do %>
        <%= icon("user", css_class: "size-5") %>
        <span>Your Name</span>
      <% end %>
    ERB

    assert_select 'h2[data-key="settings.heading"].text-2xl.font-semibold.mb-3.text-heading.flex.items-center.gap-2' do
      assert_select 'svg[data-icon="user"]', count: 1
      assert_select "span", text: "Your Name", count: 1
    end
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
    assert result.end_with?("…")
  end

  test "#post_content_preview returns content as-is when short" do
    short_content = "Short content"
    assert_equal short_content, post_content_preview(short_content)
  end

  test "#post_content_preview strips whitespace" do
    content_with_whitespace = "  Content with spaces  "
    assert_equal "Content with spaces", post_content_preview(content_with_whitespace)
  end

  test "#icon returns svg for known icon" do
    result = icon("info")
    assert_includes result, "<svg"
    assert_includes result, 'aria-hidden="true"'
    assert_includes result, 'class="shrink-0"'
  end

  test "#icon returns svg with css class" do
    result = icon("info", css_class: "size-4 text-warning")
    assert_includes result, 'class="shrink-0 size-4 text-warning"'
  end

  test "#icon carries the icon name as a data hook" do
    result = icon("info")
    assert_includes result, 'data-icon="info"'
  end

  test "#icon renders intrinsic width and height so it stays sized without CSS" do
    result = icon("info")
    assert_includes result, 'width="24"'
    assert_includes result, 'height="24"'
  end

  test "#icon returns empty string for unknown icon" do
    result = icon("nonexistent-icon")
    assert_equal "", result
  end

  test "#icon renders title attribute when provided" do
    result = icon("info", title: "Favorite")
    assert_includes result, 'title="Favorite"'
    assert_includes result, 'aria-hidden="true"'
  end

  test "#icon renders aria-label and role when aria_label provided" do
    result = icon("info", aria_label: "Favorite")
    assert_includes result, 'aria-label="Favorite"'
    assert_includes result, 'role="img"'
    assert_not_includes result, "aria-hidden"
  end

  test "#credential_state_icon should mark an unsettled record unknown rather than in progress" do
    ["pending", "validating"].each do |state|
      result = credential_state_icon(state)
      assert_includes result, 'data-icon="circle-question-mark"'
      assert_includes result, 'title="Not checked yet"'
    end
  end

  test "#credential_state_icon should render the settled states" do
    assert_includes credential_state_icon("active"), 'data-icon="circle-check"'
    assert_includes credential_state_icon("inactive"), 'data-icon="circle-x"'
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

  test "#navbar_items should return only status for suspended user" do
    user = create(:user, :suspended)
    Current.session = create(:session, user: user)

    current_page_stub = ->(_path, *_args) { false }

    self.stub(:current_page?, current_page_stub) do
      self.stub(:controller_path, "dashboard") do
        assert_equal ["Status"], navbar_items.map { |item| item[:name] }
      end
    end
  end

  test "#navbar_items should include admin panel when allowed" do
    user = create(:user)
    Current.session = create(:session, user: user)

    current_page_stub = ->(path, *_args) { path == admin_path }

    self.stub(:current_page?, current_page_stub) do
      self.stub(:controller_path, "admin/dashboard") do
        self.policy_override = ->(record) { PolicyStub.new(record == :access, false) }

        items = navbar_items
        admin_item = items.find { |item| item[:name] == "Admin Panel" }

        assert_equal admin_path, admin_item[:path]
        assert_equal true, admin_item[:active]
        assert_nil items.find { |item| item[:name] == "Dev Tools" }
      end
    end
  end

  test "#clipboard_button should carry the copied value and label the button" do
    result = clipboard_button("secret", label: "Copy token", key: "webhook.copy-token", css_class: "mt-2")

    assert_includes result, 'data-clipboard-text-value="secret"'
    assert_includes result, 'data-action="click-&gt;clipboard#copy"'
    assert_includes result, 'data-key="webhook.copy-token"'
    assert_includes result, 'title="Copy token"'
    assert_includes result, 'data-icon="clipboard"'
    assert_includes result, '<span class="sr-only">Copy token</span>'
    assert_includes result, "mt-2"
  end

  test "#navbar_items should include dev tools when allowed" do
    user = create(:user)
    Current.session = create(:session, user: user)

    current_page_stub = ->(path, *_args) { path == development_path }

    self.stub(:current_page?, current_page_stub) do
      self.stub(:controller_path, "developments") do
        self.policy_override = ->(record) { PolicyStub.new(false, record == :access) }

        items = navbar_items
        dev_item = items.find { |item| item[:name] == "Dev Tools" }

        assert_equal development_path, dev_item[:path]
        assert_equal true, dev_item[:active]
        assert_nil items.find { |item| item[:name] == "Admin Panel" }
      end
    end
  end
end
