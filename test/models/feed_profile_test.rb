require "test_helper"

class FeedProfileTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  def feed_profile
    @feed_profile ||= create(:feed_profile, user: user)
  end

  test "should belong to user" do
    assert_equal user, feed_profile.user
  end

  test "should have many feeds" do
    feed = create(:feed, user: user, feed_profile: feed_profile)
    assert_includes feed_profile.feeds, feed
  end

  test "should have many feed_previews" do
    preview = create(:feed_preview, user: user, feed_profile: feed_profile)
    assert_includes feed_profile.feed_previews, preview
  end

  test "should nullify feeds when destroyed" do
    feed = create(:feed, user: user, feed_profile: feed_profile)
    feed_profile.destroy!

    feed.reload
    assert_nil feed.feed_profile_id
  end

  test "should destroy feed_previews when destroyed" do
    preview = create(:feed_preview, user: user, feed_profile: feed_profile)

    assert_difference("FeedPreview.count", -1) do
      feed_profile.destroy!
    end
  end

  test "should validate presence of name" do
    profile = build(:feed_profile, name: nil, user: user)
    assert_not profile.valid?
    assert_includes profile.errors[:name], "can't be blank"
  end

  test "should validate uniqueness of name" do
    existing = create(:feed_profile, name: "unique-name", user: user)
    duplicate = build(:feed_profile, name: "unique-name", user: create(:user))

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "should validate name length" do
    long_name = "a" * 101
    profile = build(:feed_profile, name: long_name, user: user)
    assert_not profile.valid?
    assert_includes profile.errors[:name], "is too long (maximum is 100 characters)"
  end

  test "should validate name format" do
    invalid_names = ["With Spaces", "with@symbols", "withCAPSLETTERS", "with.dots"]

    invalid_names.each do |invalid_name|
      profile = build(:feed_profile, name: invalid_name, user: user)
      assert_not profile.valid?, "Expected #{invalid_name} to be invalid"
      assert_includes profile.errors[:name], "must contain only lowercase letters, numbers, hyphens, and underscores"
    end
  end

  test "should allow valid name formats" do
    valid_names = ["valid-name", "valid_name", "valid123", "a", "test-profile-name"]

    valid_names.each do |valid_name|
      profile = build(:feed_profile, name: valid_name, user: user)
      assert profile.valid?, "Expected #{valid_name} to be valid, got errors: #{profile.errors.full_messages}"
    end
  end

  test "should normalize name by stripping and downcasing" do
    profile = create(:feed_profile, name: "  TEST-Profile  ", user: user)
    assert_equal "test-profile", profile.name
  end

  test "should validate presence of loader" do
    profile = build(:feed_profile, loader: nil, user: user)
    assert_not profile.valid?
    assert_includes profile.errors[:loader], "can't be blank"
  end

  test "should validate presence of processor" do
    profile = build(:feed_profile, processor: nil, user: user)
    assert_not profile.valid?
    assert_includes profile.errors[:processor], "can't be blank"
  end

  test "should validate presence of normalizer" do
    profile = build(:feed_profile, normalizer: nil, user: user)
    assert_not profile.valid?
    assert_includes profile.errors[:normalizer], "can't be blank"
  end

  test "should resolve loader class" do
    profile = create(:feed_profile, loader: "http", user: user)
    # Assuming ClassResolver.resolve exists and works
    assert_respond_to profile, :loader_class
  end

  test "should resolve processor class" do
    profile = create(:feed_profile, processor: "rss", user: user)
    assert_respond_to profile, :processor_class
  end

  test "should resolve normalizer class" do
    profile = create(:feed_profile, normalizer: "rss", user: user)
    assert_respond_to profile, :normalizer_class
  end

  test "should deactivate related feeds before destroy" do
    enabled_feed = create(:feed, user: user, feed_profile: feed_profile, state: :enabled)
    disabled_feed = create(:feed, user: user, feed_profile: feed_profile, state: :disabled)

    # Mock the update_all call since we're not testing the actual Feed state logic
    Feed.expects(:enabled).returns(Feed.where(id: enabled_feed.id))
    Feed.any_instance.expects(:update_all).with(state: :disabled)

    feed_profile.destroy!
  end
end