module CredentialHelper
  # API credentials share the pending/validating/active/inactive lifecycle, so
  # they share one badge vocabulary.
  STATE_BADGES = {
    "active" => { text: "Valid", color: :success },
    "inactive" => { text: "Inactive", color: :danger }
  }.freeze

  def credential_state_badge(credential)
    state_badge(credential.state, key: "#{credential.model_name.param_key}.state_badge",
                                   data: { credential_state: credential.state })
  end

  # Shared action menu for credential list rows and show-page headers.
  def credential_actions_menu_items(credential, include_details: false)
    key_prefix = credential.model_name.param_key
    items = []
    if include_details
      items << { label: "Details", href: polymorphic_path(credential), data: { key: "#{key_prefix}.details" } }
    end
    items << { label: "Edit", href: edit_polymorphic_path(credential), data: { key: "#{key_prefix}.edit" } }

    if credential.respond_to?(:default?) && !credential.default?
      items << { label: "Make default", href: polymorphic_path([credential, :default]), method: :patch,
                 data: { key: "#{key_prefix}.make-default" } }
    end

    items << { separator: true }
    items << { label: "Delete…", href: "#",
               data: { key: "#{key_prefix}.delete", controller: "modal-trigger",
                       modal_trigger_modal_id_value: CredentialDeleteModalComponent.modal_id(credential),
                       action: "click->modal-trigger#open" } }

    items
  end

  private

  # Only a settled state gets a badge: the show pages poll until the state data
  # attribute turns up, so rendering one mid-check would stop the poller before
  # there is a verdict to show.
  def state_badge(state, key:, data:)
    badge = STATE_BADGES[state.to_s]
    return if badge.nil?

    BadgeComponent.new(text: badge[:text], color: badge[:color], key: key, data: data)
  end
end
