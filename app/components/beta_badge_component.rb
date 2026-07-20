class BetaBadgeComponent < ViewComponent::Base
  def initialize(key: nil)
    @key = key
  end

  def call
    render BadgeComponent.new(text: "Beta", color: :info, key: @key)
  end
end
