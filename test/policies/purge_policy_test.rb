require "test_helper"

class PurgePolicyTest < ActiveSupport::TestCase
  def admin_user
    @admin_user ||= create(:user, :admin)
  end

  def regular_user
    @regular_user ||= create(:user)
  end

  test "create? allows admin users" do
    assert PurgePolicy.new(admin_user, :purge).create?
  end

  test "create? denies regular users" do
    refute PurgePolicy.new(regular_user, :purge).create?
  end

  test "create? denies unauthenticated users" do
    refute PurgePolicy.new(nil, :purge).create?
  end

  test "new? delegates to create?" do
    assert PurgePolicy.new(admin_user, :purge).new?
    refute PurgePolicy.new(regular_user, :purge).new?
  end
end
