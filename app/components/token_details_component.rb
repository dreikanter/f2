class TokenDetailsComponent < ViewComponent::Base
  def initialize(access_token:)
    @access_token = access_token
  end

  def call
    render ListGroupComponent.new.tap do |component|
      items.each { component.with_item(ListGroupComponent::StatItemComponent.new(**_1)) }
    end
  end

  private

  def items
    [
      {
        label: "FreeFeed User",
        value: freefeed_user,
        key: "token.freefeed_user"
      },
      {
        label: "FreeFeed Instance",
        value: freefeed_instance,
        key: "token.host"
      },
      {
        label: "Last Used",
        value: last_used,
        key: "token.last_used"
      },
      {
        label: "Created",
        value: created,
        key: "token.created"
      }
    ]
  end

  def freefeed_user
    @access_token.owner.presence || "–"
  end

  def freefeed_instance
    URI.parse(@access_token.host).host
  end

  def last_used
    @access_token.last_used_at ? helpers.datetime_with_duration_tag(@access_token.last_used_at) : "Never"
  end

  def created
    helpers.datetime_with_duration_tag(@access_token.created_at)
  end
end
