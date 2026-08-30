# A settings-list row for one provider credential: status icon, name with an
# optional Default badge, provider name underneath, and the actions menu.
#
# Subclasses supply the two things that can't come from the record — the
# provider's display name and the noun used in the delete prompt. Routes, DOM
# ids, and test hooks are all derived from the model name, so the AI and web
# search rows stay in step by construction.
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

  def provider_name
    raise NotImplementedError, "#{self.class.name} must implement #provider_name"
  end

  # Reads mid-sentence in the delete prompt, e.g. "Delete this AI credential?".
  def credential_noun
    raise NotImplementedError, "#{self.class.name} must implement #credential_noun"
  end

  # Namespaces the data-key hooks: "ai_credential", "search_credential".
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
    helpers.tag.span(helpers.credential_status_icon(credential.state),
                     class: "inline-flex shrink-0",
                     data: { key: "#{key_prefix}.#{credential.id}.status_icon" })
  end

  def primary_element
    helpers.tag.div(helpers.safe_join([title_link, default_badge].compact),
                    class: "flex min-w-0 flex-1 items-center gap-2")
  end

  def title_link
    helpers.link_to(credential.display_name, credential_url, class: TITLE_LINK_CSS_CLASS)
  end

  def default_badge
    return unless credential.default?

    render(BadgeComponent.new(text: "Default", color: :info, key: "#{key_prefix}.default-badge"))
  end

  def secondary_element
    helpers.tag.div(provider_name, class: "truncate text-sm text-muted")
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
    items << { separator: true }
    items << { label: "Delete…", href: credential_url,
               data: { turbo_method: :delete, turbo_confirm: delete_confirm } }
    items
  end

  def delete_confirm
    "Delete this #{credential_noun}? Feeds using it will be disabled."
  end

  def credential_url
    helpers.polymorphic_path(credential)
  end

  def edit_url
    helpers.edit_polymorphic_path(credential)
  end

  def default_url
    helpers.polymorphic_path([credential, :default])
  end

  def menu_id
    "#{key_prefix.dasherize}-menu-#{credential.id}"
  end
end
