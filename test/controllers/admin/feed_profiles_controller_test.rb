require "test_helper"

class Admin::FeedProfilesControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  def admin_user
    @admin_user ||= begin
      admin = create(:user)
      create(:permission, user: admin, name: "admin")
      admin
    end
  end

  def feed_profile
    @feed_profile ||= create(:feed_profile, user: user)
  end

  def other_feed_profile
    @other_feed_profile ||= create(:feed_profile, user: create(:user), name: "other-profile")
  end

  test "should redirect to login when not authenticated" do
    get admin_feed_profiles_url
    assert_redirected_to new_session_path
  end

  test "should redirect non-admin users" do
    sign_in_as(user)
    get admin_feed_profiles_url
    assert_redirected_to root_path
    follow_redirect!
    assert_includes response.body, "Access denied"
  end

  test "should get index when authenticated as admin" do
    sign_in_as(admin_user)
    get admin_feed_profiles_url
    assert_response :success
  end

  test "should show all feed profiles in index" do
    feed_profile # create first profile
    other_feed_profile # create second profile

    sign_in_as(admin_user)
    get admin_feed_profiles_url
    assert_response :success
    assert_includes response.body, feed_profile.name
    assert_includes response.body, other_feed_profile.name
  end

  test "should get new when authenticated as admin" do
    sign_in_as(admin_user)
    get new_admin_feed_profile_url
    assert_response :success
  end

  test "should redirect non-admin from new" do
    sign_in_as(user)
    get new_admin_feed_profile_url
    assert_redirected_to root_path
  end

  test "should create feed profile when authenticated as admin" do
    sign_in_as(admin_user)

    assert_difference("FeedProfile.count", 1) do
      post admin_feed_profiles_url, params: {
        feed_profile: {
          name: "test-profile",
          loader: "http",
          processor: "rss",
          normalizer: "rss",
          user_id: user.id
        }
      }
    end

    profile = FeedProfile.last
    assert_equal "test-profile", profile.name
    assert_equal "http", profile.loader
    assert_equal "rss", profile.processor
    assert_equal "rss", profile.normalizer
    assert_equal user, profile.user
    assert_redirected_to admin_feed_profile_url(profile)
    follow_redirect!
    assert_includes response.body, "successfully created"
  end

  test "should not create feed profile with invalid data" do
    sign_in_as(admin_user)

    assert_no_difference("FeedProfile.count") do
      post admin_feed_profiles_url, params: {
        feed_profile: {
          name: "", # invalid
          loader: "http",
          processor: "rss",
          normalizer: "rss",
          user_id: user.id
        }
      }
    end

    assert_response :unprocessable_content
  end

  test "should not allow non-admin to create feed profile" do
    sign_in_as(user)

    assert_no_difference("FeedProfile.count") do
      post admin_feed_profiles_url, params: {
        feed_profile: {
          name: "test-profile",
          loader: "http",
          processor: "rss",
          normalizer: "rss",
          user_id: user.id
        }
      }
    end

    assert_redirected_to root_path
  end

  test "should show feed profile when authenticated as admin" do
    sign_in_as(admin_user)
    get admin_feed_profile_url(feed_profile)
    assert_response :success
    assert_includes response.body, feed_profile.name
    assert_includes response.body, feed_profile.loader
    assert_includes response.body, feed_profile.processor
    assert_includes response.body, feed_profile.normalizer
  end

  test "should not show feed profile to non-admin" do
    sign_in_as(user)
    get admin_feed_profile_url(feed_profile)
    assert_redirected_to root_path
  end

  test "should get edit when authenticated as admin" do
    sign_in_as(admin_user)
    get edit_admin_feed_profile_url(feed_profile)
    assert_response :success
  end

  test "should not get edit for non-admin" do
    sign_in_as(user)
    get edit_admin_feed_profile_url(feed_profile)
    assert_redirected_to root_path
  end

  test "should update feed profile when authenticated as admin" do
    sign_in_as(admin_user)

    patch admin_feed_profile_url(feed_profile), params: {
      feed_profile: {
        name: "updated-profile",
        loader: "http",
        processor: "rss",
        normalizer: "rss"
      }
    }

    assert_redirected_to admin_feed_profile_url(feed_profile)
    follow_redirect!
    assert_includes response.body, "successfully updated"

    feed_profile.reload
    assert_equal "updated-profile", feed_profile.name
  end

  test "should not update feed profile with invalid data" do
    sign_in_as(admin_user)

    patch admin_feed_profile_url(feed_profile), params: {
      feed_profile: {
        name: "", # invalid
        loader: "http"
      }
    }

    assert_response :unprocessable_content

    feed_profile.reload
    assert_not_equal "", feed_profile.name
  end

  test "should not allow non-admin to update feed profile" do
    sign_in_as(user)

    patch admin_feed_profile_url(feed_profile), params: {
      feed_profile: { name: "hacked-profile" }
    }

    assert_redirected_to root_path
  end

  test "should destroy feed profile when authenticated as admin" do
    sign_in_as(admin_user)
    profile = create(:feed_profile, user: user, name: "deletable-profile")

    assert_difference("FeedProfile.count", -1) do
      delete admin_feed_profile_url(profile)
    end

    assert_redirected_to admin_feed_profiles_url
    follow_redirect!
    assert_includes response.body, "successfully deleted"
  end

  test "should not destroy feed profile when it has dependent records" do
    sign_in_as(admin_user)
    profile_with_preview = create(:feed_profile, user: user)
    create(:feed_preview, feed_profile: profile_with_preview)

    assert_no_difference("FeedProfile.count") do
      delete admin_feed_profile_url(profile_with_preview)
    end

    assert_redirected_to admin_feed_profiles_url
    follow_redirect!
    assert_includes response.body, "Cannot delete feed profile: it is still being used"
  end

  test "should not allow non-admin to destroy feed profile" do
    sign_in_as(user)

    assert_no_difference("FeedProfile.count") do
      delete admin_feed_profile_url(feed_profile)
    end

    assert_redirected_to root_path
  end

  test "should handle missing feed profile gracefully" do
    sign_in_as(admin_user)

    get admin_feed_profile_url(id: 999999)
    assert_response :not_found
  end

  test "should display feed profile details correctly" do
    sign_in_as(admin_user)
    profile = create(:feed_profile,
                    name: "detailed-profile",
                    loader: "http",
                    processor: "rss",
                    normalizer: "rss",
                    user: user)

    get admin_feed_profile_url(profile)
    assert_response :success
    assert_includes response.body, "detailed-profile"
    assert_includes response.body, "http"
    assert_includes response.body, "rss"
    assert_includes response.body, user.email_address
  end

  test "should show user information in feed profile" do
    sign_in_as(admin_user)
    get admin_feed_profile_url(feed_profile)
    assert_response :success
    assert_includes response.body, feed_profile.user.email_address
  end

  test "should validate uniqueness of feed profile names" do
    sign_in_as(admin_user)
    existing_profile = create(:feed_profile, name: "duplicate-name", user: user)

    assert_no_difference("FeedProfile.count") do
      post admin_feed_profiles_url, params: {
        feed_profile: {
          name: "duplicate-name",
          loader: "http",
          processor: "rss",
          normalizer: "rss",
          user_id: user.id
        }
      }
    end

    assert_response :unprocessable_content
  end

  test "should require all service attributes" do
    sign_in_as(admin_user)

    # Test missing loader
    assert_no_difference("FeedProfile.count") do
      post admin_feed_profiles_url, params: {
        feed_profile: {
          name: "incomplete-profile",
          processor: "rss",
          normalizer: "rss",
          user_id: user.id
        }
      }
    end
    assert_response :unprocessable_content

    # Test missing processor
    assert_no_difference("FeedProfile.count") do
      post admin_feed_profiles_url, params: {
        feed_profile: {
          name: "incomplete-profile",
          loader: "http",
          normalizer: "rss",
          user_id: user.id
        }
      }
    end
    assert_response :unprocessable_content

    # Test missing normalizer
    assert_no_difference("FeedProfile.count") do
      post admin_feed_profiles_url, params: {
        feed_profile: {
          name: "incomplete-profile",
          loader: "http",
          processor: "rss",
          user_id: user.id
        }
      }
    end
    assert_response :unprocessable_content
  end

  test "should order feed profiles by name in index" do
    sign_in_as(admin_user)
    profile_z = create(:feed_profile, name: "z-profile", user: user)
    profile_a = create(:feed_profile, name: "a-profile", user: user)

    get admin_feed_profiles_url
    assert_response :success

    # Check that a-profile appears before z-profile in the response
    response_body = response.body
    a_position = response_body.index("a-profile")
    z_position = response_body.index("z-profile")
    assert a_position < z_position, "Profiles should be ordered alphabetically"
  end

  test "should include user information in index" do
    sign_in_as(admin_user)
    get admin_feed_profiles_url
    assert_response :success
    # Response should include user information for each profile
    assert_includes response.body, feed_profile.user.email_address
  end
end
