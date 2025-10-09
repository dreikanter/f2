require "test_helper"

class InviteTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  def other_user
    @other_user ||= create(:user)
  end

  test "should create invite with valid attributes" do
    invite = Invite.create(created_by_user: user)
    assert invite.persisted?
    assert_nil invite.invited_user
  end

  test "should require created_by_user" do
    invite = Invite.new
    assert_not invite.valid?
    assert_includes invite.errors[:created_by_user], "can't be blank"
  end

  test "used? returns false when invite has no invited_user" do
    invite = create(:invite, created_by_user: user)
    assert_not invite.used?
  end

  test "used? returns true when invite has invited_user" do
    invite = create(:invite, created_by_user: user, invited_user: other_user)
    assert invite.used?
  end

  test "belongs to created_by_user" do
    invite = create(:invite, created_by_user: user)
    assert_equal user, invite.created_by_user
  end

  test "can have invited_user" do
    invite = create(:invite, created_by_user: user, invited_user: other_user)
    assert_equal other_user, invite.invited_user
  end

  test "invited_user is optional" do
    invite = create(:invite, created_by_user: user, invited_user: nil)
    assert invite.valid?
  end
end
