require "test_helper"

class Admin::PurgesControllerTest < ActionDispatch::IntegrationTest
  def admin_user
    @admin_user ||= create(:user).tap do |u|
      create(:permission, user: u, name: "admin")
    end
  end

  def regular_user
    @regular_user ||= create(:user)
  end

  def access_token
    @access_token ||= create(:access_token, :active, user: admin_user)
  end

  test "new requires admin permission" do
    sign_in_as(regular_user)
    get new_admin_purge_path
    assert_response :forbidden
  end

  test "new shows form for admin" do
    sign_in_as(admin_user)
    create(:access_token, :active, user: admin_user)

    get new_admin_purge_path
    assert_response :success
    assert_select "h1", "Purge Group Posts"
  end

  test "create requires admin permission" do
    sign_in_as(regular_user)
    post admin_purges_path, params: { purge: { access_token_id: access_token.id, target_group: "testgroup" } }
    assert_response :forbidden
  end

  test "create schedules job and creates event" do
    sign_in_as(admin_user)

    assert_enqueued_with(job: GroupPurgeJob, args: [access_token.id, "testgroup"]) do
      assert_difference("Event.count", 1) do
        post admin_purges_path, params: { purge: { access_token_id: access_token.id, target_group: "testgroup" } }
      end
    end

    assert_redirected_to new_admin_purge_path

    event = Event.last
    assert_equal "GroupPurgeStarted", event.type
    assert_equal admin_user, event.user
    assert_equal access_token, event.subject
    assert_equal "info", event.level
    assert_equal "testgroup", event.metadata["target_group"]
  end

  test "create requires authentication" do
    post admin_purges_path, params: { purge: { access_token_id: access_token.id, target_group: "testgroup" } }
    assert_redirected_to new_session_path
  end
end
