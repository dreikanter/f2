require "test_helper"

class SystemStatusHelperTest < ActionView::TestCase
  test "#environment_badge should render production as danger" do
    result = environment_badge("production")

    assert_includes result, "production"
    assert_includes result, "bg-danger-subtle"
  end

  test "#environment_badge should render staging as warning" do
    result = environment_badge("staging")

    assert_includes result, "staging"
    assert_includes result, "bg-warning-subtle"
  end

  test "#environment_badge should render development as success" do
    result = environment_badge("development")

    assert_includes result, "development"
    assert_includes result, "bg-success-subtle"
  end

  test "#environment_badge should render unknown environments as neutral" do
    result = environment_badge("test")

    assert_includes result, "test"
    assert_includes result, "bg-surface-muted"
  end

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
