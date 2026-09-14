class Development::LlmModelPolicy < ApplicationPolicy
  def show?
    dev?
  end
end
