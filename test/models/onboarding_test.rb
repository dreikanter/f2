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

  test "next_step returns next step in sequence" do
    onboarding.update!(current_step: :intro)
    assert_equal "token", onboarding.next_step

    onboarding.update!(current_step: :token)
    assert_equal "feed", onboarding.next_step

    onboarding.update!(current_step: :feed)
    assert_equal "schedule", onboarding.next_step

    onboarding.update!(current_step: :schedule)
    assert_equal "outro", onboarding.next_step
  end

  test "next_step returns nil on last step" do
    onboarding.update!(current_step: :outro)
    assert_nil onboarding.next_step
  end

  test "current_step_number returns correct position" do
    onboarding.update!(current_step: :intro)
    assert_equal 1, onboarding.current_step_number

    onboarding.update!(current_step: :token)
    assert_equal 2, onboarding.current_step_number

    onboarding.update!(current_step: :feed)
    assert_equal 3, onboarding.current_step_number

    onboarding.update!(current_step: :schedule)
    assert_equal 4, onboarding.current_step_number

    onboarding.update!(current_step: :outro)
    assert_equal 5, onboarding.current_step_number
  end

  test "total_steps returns correct count" do
    assert_equal 5, onboarding.total_steps
  end

  test "first_step? returns true only for intro step" do
    onboarding.update!(current_step: :intro)
    assert onboarding.first_step?

    onboarding.update!(current_step: :token)
    assert_not onboarding.first_step?

    onboarding.update!(current_step: :outro)
    assert_not onboarding.first_step?
  end

  test "last_step? returns true only for outro step" do
    onboarding.update!(current_step: :intro)
    assert_not onboarding.last_step?

    onboarding.update!(current_step: :schedule)
    assert_not onboarding.last_step?

    onboarding.update!(current_step: :outro)
    assert onboarding.last_step?
  end
end
