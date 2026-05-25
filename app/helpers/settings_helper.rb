module SettingsHelper
  def access_tokens_list_component(access_tokens:)
    ListComponent.new.tap do |list|
      access_tokens.each do |access_token|
        list.with_item(ListComponent::ItemComponent.new(
          title: access_token.name,
          title_url: access_token_path(access_token),
          metadata_segments: access_token_metadata_segments(access_token),
          key: "settings.access_tokens.#{access_token.id}"
        ))
      end
    end
  end

  private

  def access_token_metadata_segments(access_token)
    owner = if access_token.owner.present?
              "#{access_token.owner}@#{access_token.host_domain}"
            else
              "Host: #{access_token.host_domain}"
            end
    used = access_token.last_used_at ? short_time_ago(access_token.last_used_at) : "Never"
    [owner, "Created: #{short_time_ago(access_token.created_at)}", "Used: #{used}"]
  end
end
