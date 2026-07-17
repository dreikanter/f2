require "test_helper"

class Admin::AvailableInvitesControllerTest < ActionDispatch::IntegrationTest
  def admin
    @admin ||= create(:user).tap { |u| u.permissions.create!(name: "admin") }
  end

  def regular_user
    @regular_user ||= create(:user)
  end

  def target_user
    @target_user ||= create(:user, available_invites: 3)
  end

  test "should update available invites as admin" do
    sign_in_as admin
    patch admin_user_available_invites_url(target_user), params: {
      user: { available_invites: 10 }
    }
    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_select "turbo-stream[action='replace'][target='available-invites-value']"
    assert_select "turbo-stream[action='replace'][target='available-invites-input-wrapper-#{target_user.id}']"
    assert_select "turbo-stream[action='replace'][target='flash-messages']" do
      assert_select "div[id='flash-messages']"
      assert_select ".bg-success-subtle", text: /Available invites updated successfully/
    end

    target_user.reload
    assert_equal 10, target_user.available_invites
  end

  test "should not update available invites to negative value" do
    sign_in_as admin
    patch admin_user_available_invites_url(target_user), params: {
      user: { available_invites: -5 }
    }
    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_select "turbo-stream[action='replace'][target='flash-messages']" do
      assert_select "div[id='flash-messages']"
      assert_select ".bg-danger-subtle", text: /Failed to update available invites/
    end

    target_user.reload
    assert_equal 3, target_user.available_invites
  end

  test "should not update available invites to blank value" do
    sign_in_as admin
    patch admin_user_available_invites_url(target_user), params: {
      user: { available_invites: "" }
    }
    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_select "turbo-stream[action='replace'][target='flash-messages']" do
      assert_select "div[id='flash-messages']"
      assert_select ".bg-danger-subtle", text: /Failed to update available invites/
    end

    target_user.reload
    assert_equal 3, target_user.available_invites
  end

  test "should not allow non-admin to update other user's available invites" do
    sign_in_as regular_user
    patch admin_user_available_invites_url(target_user), params: {
      user: { available_invites: 10 }
    }
    assert_response :redirect

    target_user.reload
    assert_equal 3, target_user.available_invites
  end

  test "should not allow user to update their own available invites" do
    sign_in_as target_user
    patch admin_user_available_invites_url(target_user), params: {
      user: { available_invites: 10 }
    }
    assert_response :redirect

    target_user.reload
    assert_equal 3, target_user.available_invites
  end

  test "should require authentication" do
    patch admin_user_available_invites_url(target_user), params: {
      user: { available_invites: 10 }
    }
    assert_redirected_to new_session_path
  end
end
