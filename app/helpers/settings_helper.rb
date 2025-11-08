module SettingsHelper
  def access_tokens_list_component(access_tokens:)
    ListGroupComponent.new.tap do |list|
      access_tokens.each do |access_token|
        list.with_item(ListGroupComponent::AccessTokenItemComponent.new(
          access_token: access_token,
          key: "settings.access_tokens.#{access_token.id}"
        ))
      end
    end
  end
end
