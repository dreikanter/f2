class FreefeedUserComponent < ViewComponent::Base
  def initialize(username:)
    @username = username
  end
end
