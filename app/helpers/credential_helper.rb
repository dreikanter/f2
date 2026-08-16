module CredentialHelper
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
end
