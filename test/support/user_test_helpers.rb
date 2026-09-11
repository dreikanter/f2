module UserTestHelpers
  def regular_user
    @regular_user ||= create(:user)
  end

  def other_user
    @other_user ||= create(:user)
  end

  def admin_user
    @admin_user ||= create(:user, :admin)
  end

  def dev_user
    @dev_user ||= create(:user, :dev)
  end
end
