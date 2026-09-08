class FreefeedInstanceBadgeComponent < BadgeComponent
  COLORS = {
    "candy" => :candy,
    "beta" => :beta
  }.freeze

  def initialize(access_token:, key: nil)
    @label = access_token&.instance_label
    super(text: @label, color: COLORS.fetch(@label, :neutral), size: :sm, key: key)
  end

  def render?
    @label.present?
  end
end
