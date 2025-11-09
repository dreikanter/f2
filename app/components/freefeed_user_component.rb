class FreefeedUserComponent < ViewComponent::Base
  def initialize(user:)
    @user = user
  end

  private

  def username
    @user.is_a?(Hash) ? @user["username"] || @user[:username] : @user
  end
end
