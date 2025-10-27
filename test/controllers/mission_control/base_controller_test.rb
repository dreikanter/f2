require "test_helper"

# Extend TestAdapter with Mission Control interface for testing
# Note: We cannot use Minitest stubs because TestAdapter doesn't have these methods,
# and Minitest's stub only works with existing methods
ActiveJob::QueueAdapters::TestAdapter.include(MissionControl::Jobs::Adapter)

ActiveJob::QueueAdapters::TestAdapter.class_eval do
  def queue_names
    []
  end

  def queues
    []
  end

  def jobs_count(*)
    0
  end
end

class MissionControl::BaseControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user, state: :active)
  end

  def admin_user
    @admin_user ||= begin
      admin = create(:user, state: :active)
      create(:permission, user: admin, name: "admin")
      admin
    end
  end

  test "should allow admin user to access jobs dashboard" do
    sign_in_as(admin_user)
    get "/jobs"

    assert_response :success
  end

  test "should redirect non-admin user" do
    sign_in_as(user)
    get "/jobs"

    assert_response :redirect
    assert_redirected_to root_path
    assert_equal "Access denied. You don't have permission to perform this action.", flash[:alert]
  end

  test "should redirect unauthenticated user to login" do
    get "/jobs"

    assert_response :redirect
    assert_match %r{/session/new}, response.location
  end
end
