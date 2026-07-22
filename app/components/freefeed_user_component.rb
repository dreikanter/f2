class FreefeedUserComponent < ViewComponent::Base
  def initialize(user:)
    @user = user
  end

  private

  def username
    @user["username"] || @user[:username]
  end

  def userpic_url
    @user["profile_picture_url"] || @user[:profile_picture_url]
  end
end
