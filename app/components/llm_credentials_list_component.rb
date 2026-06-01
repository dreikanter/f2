class LlmCredentialsListComponent < ViewComponent::Base
  MAKE_DEFAULT_CLASSES = "inline-flex items-center justify-center whitespace-nowrap rounded-md border border-slate-200 bg-white px-3 py-1.5 text-sm font-medium text-slate-700 shadow-sm transition hover:bg-slate-50".freeze
  DELETE_CLASSES = "inline-flex items-center justify-center whitespace-nowrap rounded-md border border-red-200 bg-white px-3 py-1.5 text-sm font-medium text-red-700 shadow-sm transition hover:bg-red-50".freeze
  DELETE_CONFIRM = "Delete this AI credential? Feeds using it will be disabled.".freeze

  def initialize(credentials:)
    @credentials = credentials
  end

  def call
    render(ListComponent.new) do |list|
      @credentials.each do |credential|
        list.with_item(ListComponent::ItemComponent.new(
          title: credential.display_name,
          title_url: helpers.llm_credential_path(credential),
          badge: default_badge_for(credential),
          metadata_segments: metadata_segments_for(credential),
          note: inactive_note_for(credential),
          actions: actions_for(credential),
          key: "llm_credential.#{credential.id}"
        ))
      end
    end
  end

  private

  def default_badge_for(credential)
    return unless credential.is_default?

    render(BadgeComponent.new(text: "Default", color: :blue, key: "llm_credential.default-badge"))
  end

  def metadata_segments_for(credential)
    provider_name = LlmProvider.find(credential.provider)&.display_name
    [provider_name, "status: #{credential.state}"].compact
  end

  def inactive_note_for(credential)
    return unless credential.inactive?

    content_tag(:p, "This key didn't work. Open it to add a new one.", class: "text-sm text-red-600")
  end

  def actions_for(credential)
    buttons = []
    unless credential.is_default?
      buttons << helpers.button_to(
        "Make default",
        helpers.llm_credential_default_path(credential),
        method: :patch,
        class: MAKE_DEFAULT_CLASSES,
        data: { key: "llm_credential.make-default" }
      )
    end
    buttons << helpers.button_to(
      "Delete",
      helpers.llm_credential_path(credential),
      method: :delete,
      form: { data: { turbo_confirm: DELETE_CONFIRM } },
      class: DELETE_CLASSES,
      data: { key: "llm_credential.delete" }
    )
    safe_join(buttons)
  end
end
