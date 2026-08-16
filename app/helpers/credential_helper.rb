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
end
