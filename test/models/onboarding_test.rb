require "test_helper"

class OnboardingTest < ActiveSupport::TestCase
  def onboarding
    @onboarding ||= create(:user, :with_onboarding).onboarding
  end

  test "should be destroyed with user" do
    user = create(:user, :with_onboarding)
    onboarding_id = user.onboarding.id

    user.destroy
    assert_not Onboarding.exists?(onboarding_id)
  end

  test "should enforce one onboarding per user" do
    user = create(:user, :with_onboarding)

    assert_raises ActiveRecord::RecordNotUnique do
      Onboarding.create!(user: user)
    end
  end

  test "can be created without access_token or feed" do
    user = create(:user)
    onboarding = Onboarding.create!(user: user)

    assert_nil onboarding.access_token
    assert_nil onboarding.feed
  end

  test "can be associated with access_token" do
    user = create(:user)
    access_token = create(:access_token, user: user)
    onboarding = Onboarding.create!(user: user, access_token: access_token)

    assert_equal access_token, onboarding.access_token
  end

  test "can be associated with feed" do
    user = create(:user)
    feed = create(:feed, user: user)
    onboarding = Onboarding.create!(user: user, feed: feed)

    assert_equal feed, onboarding.feed
  end

  test "can be associated with both access_token and feed" do
    user = create(:user)
    access_token = create(:access_token, user: user)
    feed = create(:feed, user: user)
    onboarding = Onboarding.create!(user: user, access_token: access_token, feed: feed)

    assert_equal access_token, onboarding.access_token
    assert_equal feed, onboarding.feed
  end

  test "token_setup? returns true when no access_token" do
    user = create(:user)
    onboarding = Onboarding.create!(user: user)

    assert onboarding.token_setup?
  end

  test "token_setup? returns false when access_token exists" do
    user = create(:user)
    access_token = create(:access_token, user: user)
    onboarding = Onboarding.create!(user: user, access_token: access_token)

    assert_not onboarding.token_setup?
  end

  test "feed_setup? returns false when no access_token" do
    user = create(:user)
    onboarding = Onboarding.create!(user: user)

    assert_not onboarding.feed_setup?
  end

  test "feed_setup? returns true when access_token exists but no feed" do
    user = create(:user)
    access_token = create(:access_token, user: user)
    onboarding = Onboarding.create!(user: user, access_token: access_token)

    assert onboarding.feed_setup?
  end

  test "feed_setup? returns false when both access_token and feed exist" do
    user = create(:user)
    access_token = create(:access_token, user: user)
    feed = create(:feed, user: user)
    onboarding = Onboarding.create!(user: user, access_token: access_token, feed: feed)

    assert_not onboarding.feed_setup?
  end

  test "token_setup? uses access_token_id directly" do
    user = create(:user)
    access_token = create(:access_token, user: user)
    onboarding = Onboarding.create!(user: user, access_token: access_token)

    # Manually set access_token_id to nil without loading association
    onboarding.update_column(:access_token_id, nil)
    assert onboarding.token_setup?
  end

  test "feed_setup? uses access_token_id and feed_id directly" do
    user = create(:user)
    access_token = create(:access_token, user: user)
    onboarding = Onboarding.create!(user: user, access_token: access_token)

    # Manually set feed_id to nil without loading association
    onboarding.update_column(:feed_id, nil)
    assert onboarding.feed_setup?
  end

  test "belongs_to user" do
    user = create(:user)
    onboarding = Onboarding.create!(user: user)

    assert_equal user, onboarding.user
  end

  test "requires user" do
    assert_raises ActiveRecord::RecordInvalid do
      Onboarding.create!(user: nil)
    end
  end
end
