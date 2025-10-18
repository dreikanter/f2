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
end
