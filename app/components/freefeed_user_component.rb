class FreefeedUserComponent < ViewComponent::Base
  def initialize(username:, avatar_size: "medium")
    @username = username
    @avatar_size = avatar_size
  end
end
