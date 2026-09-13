module UserTestHelpers
  def regular_user
    users(:regular_user)
  end

  def other_user
    users(:unrelated_user)
  end

  def admin_user
    users(:admin_user)
  end

  def dev_user
    users(:dev_user)
  end
end
