# A settings-list row for any API credential exposing state, display_name, and
# provider_name. Default selection is an optional capability: records defining
# #default? receive the badge and action; access tokens do not.
class CredentialListItemComponent < ListItemComponent
  def initialize(credential:)
    super()
    @credential = credential
  end

  def before_render
    with_icon { icon_element }
    with_primary { primary_element }
    with_secondary { secondary_element }
    with_trailing { menu }
  end

  private

  attr_reader :credential

  def key_prefix
    credential.model_name.param_key
  end

  def li_id
    helpers.dom_id(credential)
  end

  def li_data
    { key: "#{key_prefix}.#{credential.id}" }
  end

  def row_css_class
    HOVER_ROW_CSS_CLASS
  end

  def icon_element
    helpers.tag.span(helpers.credential_state_icon(credential.state),
                     class: "inline-flex shrink-0",
                     data: { key: "#{key_prefix}.#{credential.id}.state_icon" })
  end

  def primary_element
    helpers.tag.div(helpers.safe_join([title_link, default_badge].compact),
                    class: "flex min-w-0 flex-1 items-center gap-2")
  end

  def title_link
    helpers.link_to(credential.display_name, credential_url, class: TITLE_LINK_CSS_CLASS)
  end

  def default_badge
    return unless defaultable? && credential.default?

    render(BadgeComponent.new(text: "Default", color: :info, key: "#{key_prefix}.default-badge"))
  end

  def secondary_element
    helpers.tag.div(credential.provider_name, class: "truncate text-sm text-muted")
  end

  def menu
    render(DropdownMenuComponent.new(menu_id: menu_id, items: menu_items, width: "w-40"))
  end

  def menu_items
    helpers.credential_actions_menu_items(credential, include_details: true)
  end

  def defaultable?
    credential.respond_to?(:default?)
  end

  def credential_url
    helpers.polymorphic_path(credential)
  end

  def menu_id
    "#{key_prefix.dasherize}-menu-#{credential.id}"
  end
end
