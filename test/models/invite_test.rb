require "test_helper"

class InviteTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  test ".create should create invite with valid attributes" do
    invite = Invite.create(created_by_user: user)
    assert invite.persisted?
    assert_nil invite.invited_user
  end

  test "#valid? should require created_by_user" do
    invite = Invite.new
    assert_not invite.valid?
    assert invite.errors.of_kind?(:created_by_user, :blank)
  end

  test "#used? should return false when the invite has no invited_user" do
    invite = create(:invite, created_by_user: user)
    assert_not invite.used?
  end

  test "#used? should return true when the invite has an invited_user" do
    invite = create(:invite, created_by_user: user, invited_user: other_user)
    assert invite.used?
  end

  test "#created_by_user should return the creator" do
    invite = create(:invite, created_by_user: user)
    assert_equal user, invite.created_by_user
  end

  test "#invited_user should return the invited user" do
    invite = create(:invite, created_by_user: user, invited_user: other_user)
    assert_equal other_user, invite.invited_user
  end

  test "#valid? should allow a missing invited_user" do
    invite = create(:invite, created_by_user: user, invited_user: nil)
    assert invite.valid?
  end
end
