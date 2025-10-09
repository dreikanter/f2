require "test_helper"

class InvitePolicyTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user, available_invites: 5)
  end

  def other_user
    @other_user ||= create(:user)
  end

  def admin
    @admin ||= create(:user).tap { |u| u.permissions.create!(name: "admin") }
  end

  def invite
    @invite ||= create(:invite, created_by_user: user)
  end

  def used_invite
    @used_invite ||= create(:invite, created_by_user: user, invited_user: other_user)
  end

  def other_users_invite
    @other_users_invite ||= create(:invite, created_by_user: other_user)
  end

  test "index? returns true for authenticated user" do
    policy = InvitePolicy.new(user, Invite)
    assert policy.index?
  end

  test "create? returns true when user has available invites" do
    policy = InvitePolicy.new(user, Invite)
    assert policy.create?
  end

  test "create? returns false when user has no available invites" do
    user.update!(available_invites: 0)
    policy = InvitePolicy.new(user, Invite)
    assert_not policy.create?
  end

  test "create? returns false when user has used all available invites" do
    user.update!(available_invites: 1)
    create(:invite, created_by_user: user)
    policy = InvitePolicy.new(user, Invite)
    assert_not policy.create?
  end

  test "destroy? returns true for own unused invite" do
    policy = InvitePolicy.new(user, invite)
    assert policy.destroy?
  end

  test "destroy? returns false for used invite" do
    policy = InvitePolicy.new(user, used_invite)
    assert_not policy.destroy?
  end

  test "destroy? returns false for other user's invite" do
    policy = InvitePolicy.new(user, other_users_invite)
    assert_not policy.destroy?
  end

  test "destroy? returns true for admin even for other user's unused invite" do
    policy = InvitePolicy.new(admin, other_users_invite)
    assert policy.destroy?
  end

  test "destroy? returns false for admin if invite is used" do
    other_used_invite = create(:invite, created_by_user: other_user, invited_user: user)
    policy = InvitePolicy.new(admin, other_used_invite)
    assert_not policy.destroy?
  end

  test "scope returns user's own invites" do
    create(:invite, created_by_user: user)
    create(:invite, created_by_user: user)
    create(:invite, created_by_user: other_user)

    scope = InvitePolicy::Scope.new(user, Invite).resolve
    assert_equal 2, scope.count
    assert scope.all? { |i| i.created_by_user_id == user.id }
  end
end
