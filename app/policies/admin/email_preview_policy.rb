class Admin::EmailPreviewPolicy < ApplicationPolicy
  def index?
    dev?
  end

  def show?
    dev?
  end
end
