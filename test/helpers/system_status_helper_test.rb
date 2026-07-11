require "test_helper"

class SystemStatusHelperTest < ActionView::TestCase
  test "#revision_commit_link should link the short hash to the commit page" do
    result = revision_commit_link("0123456", "0123456789abcdef")

    assert_includes result, "#{F2Rails::GITHUB_REPO_URL}/commit/0123456789abcdef"
    assert_includes result, "<code"
    assert_includes result, "0123456"
  end

  test "#revision_commit_link should fall back to the short hash without a full revision" do
    result = revision_commit_link("0123456", nil)

    assert_includes result, "#{F2Rails::GITHUB_REPO_URL}/commit/0123456"
  end
end
