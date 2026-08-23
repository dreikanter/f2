module CredentialHelper
  # Access tokens and credentials share the pending/validating/active/inactive
  # lifecycle, so they share one badge vocabulary.
  STATUS_BADGES = {
    "active" => { text: "Valid", color: :success },
    "inactive" => { text: "Inactive", color: :danger }
  }.freeze

  def access_token_status_badge(access_token)
    status_badge(access_token.status, key: "access_token.status_badge", data: { status: access_token.status })
  end

  def credential_status_badge(credential)
    status_badge(credential.state, key: "#{credential.model_name.param_key}.status_badge",
                                   data: { credential_state: credential.state })
  end

  # Header action menu for a credential's show page. Delete sits below a
  # separator so a destructive click isn't adjacent to the routine actions.
  def credential_actions_menu_items(credential, delete_confirm:)
    key_prefix = credential.model_name.param_key
    items = [{ label: "Edit", href: edit_polymorphic_path(credential), data: { key: "#{key_prefix}.edit" } }]

    unless credential.default?
      items << { label: "Make default", href: polymorphic_path([credential, :default]), method: :patch,
                 data: { key: "#{key_prefix}.make-default" } }
    end

    items << { separator: true }
    items << { label: "Delete…", href: polymorphic_path(credential), method: :delete,
               data: { key: "#{key_prefix}.delete", turbo_confirm: delete_confirm } }

    items
  end

  # Access tokens have no default flag, and deletion goes through the
  # confirmation modal rendered alongside the page rather than a prompt.
  def access_token_actions_menu_items(access_token)
    [
      { label: "Edit", href: edit_access_token_path(access_token), data: { key: "access_token.edit" } },
      { separator: true },
      { label: "Delete…", href: "#",
        data: { key: "access_token.delete", controller: "modal-trigger",
                modal_trigger_modal_id_value: "delete-token-modal", action: "click->modal-trigger#open" } }
    ]
  end

  private

  # Only a settled state gets a badge: the show pages poll until the state data
  # attribute turns up, so rendering one mid-check would stop the poller before
  # there is a verdict to show.
  def status_badge(state, key:, data:)
    badge = STATUS_BADGES[state.to_s]
    return if badge.nil?

    BadgeComponent.new(text: badge[:text], color: badge[:color], key: key, data: data)
  end
end
