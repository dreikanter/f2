class AccessTokensListComponent < ViewComponent::Base
  def initialize(access_tokens:)
    @access_tokens = access_tokens
  end

  def call
    render(ListComponent.new) do |list|
      @access_tokens.each do |access_token|
        list.with_item(ListComponent::ItemComponent.new(
          title: access_token.name,
          title_url: helpers.access_token_path(access_token),
          metadata_segments: metadata_segments_for(access_token),
          key: "settings.access_tokens.#{access_token.id}"
        ))
      end
    end
  end

  private

  def metadata_segments_for(access_token)
    owner = if access_token.owner.present?
      "#{access_token.owner}@#{access_token.host_domain}"
    else
      "Host: #{access_token.host_domain}"
    end
    used = access_token.last_used_at ? helpers.short_time_ago(access_token.last_used_at) : "Never"
    [owner, "Created: #{helpers.short_time_ago(access_token.created_at)}", "Used: #{used}"]
  end
end
