class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def index?
    false
  end

  def show?
    false
  end

  def create?
    false
  end

  def new?
    create?
  end

  def update?
    false
  end

  def edit?
    update?
  end

  def destroy?
    false
  end

  class Scope
    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      raise NotImplementedError, "You must define #resolve in #{self.class}"
    end

    private

    attr_reader :user, :scope

    def admin?
      user&.admin?
    end

    # The resolutions policies share. A signed-out visitor sees nothing in all
    # of them, so no policy has to spell that branch out.

    def own_records(owner = :user)
      user ? scope.where(owner => user) : scope.none
    end

    def own_feed_records
      user ? scope.joins(:feed).where(feeds: { user: user }) : scope.none
    end

    def admin_or_own_records(owner = :user)
      admin? ? scope.all : own_records(owner)
    end

    def admin_records
      admin? ? scope.all : scope.none
    end
  end

  private

  def authenticated?
    user.present?
  end

  def admin?
    user&.admin?
  end

  def dev?
    user&.dev?
  end
end
