require "test_helper"

class EventEntityPathsTest < ActiveSupport::TestCase
  def paths
    @paths ||= EventEntityPaths.new
  end

  test "#path_for should resolve owner-facing entity pages" do
    assert_equal "/feeds/abc", paths.path_for("Feed", "abc")
    assert_equal "/events/abc", paths.path_for("Event", "abc")
    assert_equal "/posts/abc", paths.path_for("Post", "abc")
    assert_equal "/access_tokens/abc", paths.path_for("AccessToken", "abc")
  end

  test "#path_for should return nil for entities without a page" do
    assert_nil paths.path_for("User", "abc")
    assert_nil paths.path_for("JobRun", "abc")
    assert_nil paths.path_for(nil, "abc")
  end
end
