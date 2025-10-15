require "test_helper"

class OnboardingTest < ActiveSupport::TestCase
  test "should be automatically created with new user" do
    user = User.create!(email_address: "test@example.com", password: "password123")
    assert_not_nil user.onboarding
  end

  test "should be destroyed with user" do
    user = create(:user, :with_onboarding)
    onboarding_id = user.onboarding.id

    user.destroy
    assert_nil Onboarding.find_by(id: onboarding_id)
  end

  test "should enforce one onboarding per user" do
    user = User.create!(email_address: "duplicate@example.com", password: "password123")

    assert_raises ActiveRecord::RecordNotUnique do
      Onboarding.create!(user: user)
    end
  end
end
