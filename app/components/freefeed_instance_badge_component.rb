# Marks a feed or token that targets a non-production FreeFeed instance.
# Renders nothing for the main freefeed.net, since that's the default and
# needs no marker. Sized to sit inline with the surrounding text.
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
