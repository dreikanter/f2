require "test_helper"

class IdentifierHelperTest < ActionView::TestCase
  test "#short_uuid returns the final five characters" do
    assert_equal "1674a", short_uuid("019f5bd6-d55f-7ac2-9d75-15be0cf1674a")
  end

  test "#uuid_label adds a prefix without an integer-style hash" do
    assert_equal "Feed ec464", uuid_label("019f5bd6-d5b7-79e3-a943-8bdbb0fec464", prefix: "Feed")
  end

  test "#uuid_reference links the compact label while preserving the full UUID" do
    uuid = "019f5bd6-d55f-7ac2-9d75-15be0cf1674a"
    result = uuid_reference(uuid, path: "/admin/users/#{uuid}", prefix: "User")

    assert_dom_equal %(<a title="#{uuid}" class="#{IdentifierHelper::UUID_LINK_CLASSES}" href="/admin/users/#{uuid}">User 1674a</a>), result
  end

  test "#uuid_reference renders plain text when no target page is available" do
    uuid = "019f5bd6-d5b7-79e3-a943-8bdbb0fec464"
    result = uuid_reference(uuid, prefix: "Feed")

    assert_dom_equal %(<span title="#{uuid}" class="#{IdentifierHelper::UUID_LINK_CLASSES}">Feed ec464</span>), result
  end
end
