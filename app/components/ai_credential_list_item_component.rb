class AiCredentialListItemComponent < ListItemComponent
  DELETE_CONFIRM = "Delete this AI credential? Feeds using it will be disabled.".freeze

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

  def li_id
    helpers.dom_id(credential)
  end

  def li_data
    { key: "ai_credential.#{credential.id}" }
  end

  def row_css_class
    HOVER_ROW_CSS_CLASS
  end

  def icon_element
    helpers.tag.span(helpers.credential_status_icon(credential.state),
                     class: "inline-flex shrink-0", data: { key: "ai_credential.#{credential.id}.status_icon" })
  end

  def primary_element
    helpers.tag.div(helpers.safe_join([title_link, default_badge].compact),
                    class: "flex min-w-0 flex-1 items-center gap-2")
  end

  def title_link
    helpers.link_to(credential.display_name, credential_url,
                    class: "truncate text-base text-heading transition hover:text-heading rounded-sm outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-white")
  end

  def default_badge
    return unless credential.default?

    render(BadgeComponent.new(text: "Default", color: :info, key: "ai_credential.default-badge"))
  end

  def secondary_element
    helpers.tag.div(provider_name, class: "truncate text-sm text-muted")
  end

  def provider_name
    credential.llm_provider.display_name
  end

  def menu
    render(DropdownMenuComponent.new(menu_id: menu_id, items: menu_items, width: "w-40"))
  end

  def menu_items
    items = [
      { label: "Details", href: credential_url },
      { label: "Edit", href: edit_url }
    ]
    items << { label: "Make default", href: default_url, data: { turbo_method: :patch } } unless credential.default?
    items << { label: "Delete…", href: credential_url, data: { turbo_method: :delete, turbo_confirm: DELETE_CONFIRM } }
    items
  end

  def credential_url
    helpers.ai_credential_path(credential)
  end

  def edit_url
    helpers.edit_ai_credential_path(credential)
  end

  def default_url
    helpers.ai_credential_default_path(credential)
  end

  def menu_id
    "ai-credential-menu-#{credential.id}"
  end
end
