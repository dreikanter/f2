class FreefeedUserComponent < ViewComponent::Base
  def initialize(user:)
    @user = user
  end

  private

  def username
    @user["username"] || @user[:username]
  end
end
