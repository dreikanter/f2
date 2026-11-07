class FeedRefreshStatusComponent < ViewComponent::Base
  attr_reader :status

  def initialize(status:)
    @status = status
  end
end
