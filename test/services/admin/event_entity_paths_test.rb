require "test_helper"

class Admin::EventEntityPathsTest < ActiveSupport::TestCase
  def paths
    @paths ||= Admin::EventEntityPaths.new
  end

  test "#path_for should resolve operator pages for admin-managed entities" do
    assert_equal "/admin/feeds/abc", paths.path_for("Feed", "abc")
    assert_equal "/admin/users/abc", paths.path_for("User", "abc")
    assert_equal "/admin/events/abc", paths.path_for("Event", "abc")
  end

  test "#path_for should keep owner pages for entities without an admin page" do
    assert_equal "/access_tokens/abc", paths.path_for("AccessToken", "abc")
    assert_equal "/ai_credentials/abc", paths.path_for("AiCredential", "abc")
  end

  test "#path_for should return nil for unknown entity types" do
    assert_nil paths.path_for("JobRun", "abc")
  end
end
