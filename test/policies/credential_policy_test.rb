require "test_helper"

# Exercises the shared rules through both concrete subclasses, so a policy that
# stops inheriting them fails here rather than silently widening access.
class CredentialPolicyTest < ActiveSupport::TestCase
  CREDENTIALS = {
    AiCredentialPolicy => :ai_credential,
    SearchCredentialPolicy => :search_credential
  }.freeze

  def owner
    @owner ||= create(:user)
  end

  def other_user
    @other_user ||= create(:user)
  end

  def admin_user
    @admin_user ||= begin
      user = create(:user)
      create(:permission, user: user, name: "admin")
      user
    end
  end

  def each_policy
    CREDENTIALS.each do |policy_class, factory|
      record = create(factory, user: owner)
      yield policy_class, record
    end
  end

  test "#index? should allow any signed-in user and deny anonymous" do
    each_policy do |policy_class, record|
      assert policy_class.new(owner, record).index?, policy_class.name
      assert policy_class.new(other_user, record).index?, policy_class.name
      assert_not policy_class.new(nil, record).index?, policy_class.name
    end
  end

  test "#create? should allow any signed-in user and deny anonymous" do
    each_policy do |policy_class, record|
      assert policy_class.new(owner, record).create?, policy_class.name
      assert_not policy_class.new(nil, record).create?, policy_class.name
    end
  end

  test "#show? should allow the owner and an admin, and deny everyone else" do
    each_policy do |policy_class, record|
      assert policy_class.new(owner, record).show?, policy_class.name
      assert policy_class.new(admin_user, record).show?, policy_class.name
      assert_not policy_class.new(other_user, record).show?, policy_class.name
      assert_not policy_class.new(nil, record).show?, policy_class.name
    end
  end

  test "#update? should allow the owner and an admin, and deny everyone else" do
    each_policy do |policy_class, record|
      assert policy_class.new(owner, record).update?, policy_class.name
      assert policy_class.new(admin_user, record).update?, policy_class.name
      assert_not policy_class.new(other_user, record).update?, policy_class.name
      assert_not policy_class.new(nil, record).update?, policy_class.name
    end
  end

  test "#destroy? should allow the owner and an admin, and deny everyone else" do
    each_policy do |policy_class, record|
      assert policy_class.new(owner, record).destroy?, policy_class.name
      assert policy_class.new(admin_user, record).destroy?, policy_class.name
      assert_not policy_class.new(other_user, record).destroy?, policy_class.name
      assert_not policy_class.new(nil, record).destroy?, policy_class.name
    end
  end

  test "#edit? and #new? should follow update? and create?" do
    each_policy do |policy_class, record|
      policy = policy_class.new(owner, record)

      assert_equal policy.update?, policy.edit?, policy_class.name
      assert_equal policy.create?, policy.new?, policy_class.name
    end
  end

  # The subclasses declare no Scope of their own, so this also pins the constant
  # lookup that reaches CredentialPolicy::Scope through the superclass.
  test "Scope should return the user's own records" do
    each_policy do |policy_class, record|
      foreign = create(CREDENTIALS.fetch(policy_class), user: other_user)
      resolved = policy_class::Scope.new(owner, record.class.all).resolve

      assert_includes resolved, record, policy_class.name
      assert_not_includes resolved, foreign, policy_class.name
    end
  end

  test "Scope should return every record for an admin" do
    each_policy do |policy_class, record|
      foreign = create(CREDENTIALS.fetch(policy_class), user: other_user)
      resolved = policy_class::Scope.new(admin_user, record.class.all).resolve

      assert_includes resolved, record, policy_class.name
      assert_includes resolved, foreign, policy_class.name
    end
  end

  test "Scope should return nothing for an anonymous visitor" do
    each_policy do |policy_class, record|
      resolved = policy_class::Scope.new(nil, record.class.all).resolve

      assert_empty resolved, policy_class.name
    end
  end
end
