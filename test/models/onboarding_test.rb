require "test_helper"

class OnboardingTest < ActiveSupport::TestCase
  test "should be destroyed with user" do
    user = create(:user, :with_onboarding)
    onboarding_id = user.onboarding.id

    user.destroy
    assert_nil Onboarding.find_by(id: onboarding_id)
  end

  test "should enforce one onboarding per user" do
    user = create(:user, :with_onboarding)

    assert_raises ActiveRecord::RecordNotUnique do
      Onboarding.create!(user: user)
    end
  end
end
