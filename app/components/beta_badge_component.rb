class BetaBadgeComponent < BadgeComponent
  def initialize(key: nil)
    super(text: "Beta", color: :info, key: key)
  end
end
