require "test_helper"

class EventPolicyTest < ActiveSupport::TestCase
  def admin_user
    @admin_user ||= begin
      user = create(:user)
      create(:permission, user: user, name: "admin")
      user
    end
  end

  def regular_user
    @regular_user ||= create(:user)
  end

  def event
    @event ||= create(:event)
  end

  test "admin users can view events index" do
    policy = EventPolicy.new(admin_user, Event)

    assert policy.index?
  end

  test "regular users cannot view events index" do
    policy = EventPolicy.new(regular_user, Event)

    assert_not policy.index?
  end

  test "unauthenticated users cannot view events index" do
    policy = EventPolicy.new(nil, Event)

    assert_not policy.index?
  end

  test "admin users can view specific events" do
    policy = EventPolicy.new(admin_user, event)

    assert policy.show?
  end

  test "regular users cannot view specific events" do
    policy = EventPolicy.new(regular_user, event)

    assert_not policy.show?
  end

  test "unauthenticated users cannot view specific events" do
    policy = EventPolicy.new(nil, event)

    assert_not policy.show?
  end

  test "scope returns all events for admin users" do
    create(:event, type: "Event1")
    create(:event, type: "Event2")

    scope = EventPolicy::Scope.new(admin_user, Event).resolve

    assert_equal 2, scope.count
  end

  test "scope returns no events for regular users" do
    create(:event, type: "Event1")
    create(:event, type: "Event2")

    scope = EventPolicy::Scope.new(regular_user, Event).resolve

    assert_equal 0, scope.count
  end

  test "scope returns no events for unauthenticated users" do
    create(:event, type: "Event1")
    create(:event, type: "Event2")

    scope = EventPolicy::Scope.new(nil, Event).resolve

    assert_equal 0, scope.count
  end
end
