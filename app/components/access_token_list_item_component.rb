class AccessTokenListItemComponent < ListItemComponent
  def initialize(access_token:)
    super()
    @access_token = access_token
  end

  def before_render
    with_icon { icon_element }
    with_primary { primary_element }
    with_secondary { secondary_element }
    with_trailing { menu }
  end

  private

  attr_reader :access_token

  def li_id
    helpers.dom_id(access_token)
  end

  def li_data
    { key: "settings.access_tokens.#{access_token.id}" }
  end

  def row_css_class
    "transition duration-75 hover:bg-surface-muted"
  end

  def icon_element
    helpers.tag.span(helpers.credential_status_icon(access_token.status),
                     class: "inline-flex shrink-0", data: { key: "access_token.#{access_token.id}.status_icon" })
  end

  def primary_element
    helpers.link_to(access_token.name, token_url,
                    class: "truncate text-base text-slate-900 transition hover:text-slate-700 rounded-sm outline-none focus-visible:ring-2 focus-visible:ring-sky-500 focus-visible:ring-offset-2 focus-visible:ring-offset-white")
  end

  def secondary_element
    helpers.tag.div(helpers.safe_join(meta_segments, helpers.middot),
                    class: "truncate text-sm text-faint")
  end

  def meta_segments
    [
      helpers.tag.span(owner_label),
      helpers.tag.span("Created #{helpers.short_time_ago(access_token.created_at)}"),
      helpers.tag.span(used_label)
    ]
  end

  def owner_label
    if access_token.owner.present?
      "@#{access_token.owner} at #{access_token.host_domain}"
    else
      access_token.host_domain
    end
  end

  def used_label
    return "Never used" unless access_token.last_used_at

    "Used #{helpers.short_time_ago(access_token.last_used_at)}"
  end

  def menu
    render(DropdownMenuComponent.new(menu_id: menu_id, items: menu_items, width: "w-40"))
  end

  def menu_items
    [
      { label: "Edit", href: edit_url },
      { label: "Delete…", href: "#",
        data: { controller: "modal-trigger", modal_trigger_modal_id_value: delete_modal_id, action: "click->modal-trigger#open" } }
    ]
  end

  def token_url
    helpers.access_token_path(access_token)
  end

  def edit_url
    helpers.edit_access_token_path(access_token)
  end

  def menu_id
    "access-token-menu-#{access_token.id}"
  end

  def delete_modal_id
    "delete-token-modal-#{access_token.id}"
  end
end
