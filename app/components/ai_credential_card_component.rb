class AiCredentialCardComponent < ViewComponent::Base
  def initialize(credential:)
    @credential = credential
  end

  private

  attr_reader :credential

  def credential_url
    helpers.ai_credential_path(credential)
  end

  def edit_url
    helpers.edit_ai_credential_path(credential)
  end

  def provider_name
    LlmProvider.find(credential.provider).display_name
  end

  def default?
    credential.default?
  end

  def status_badge
    case credential.state.to_sym
    when :pending, :validating then BadgeComponent.new(text: "Checking", color: :gray, key: "ai_credential.status-badge")
    when :active               then BadgeComponent.new(text: "Active", color: :green, key: "ai_credential.status-badge")
    when :inactive             then BadgeComponent.new(text: "Inactive", color: :red, key: "ai_credential.status-badge")
    end
  end

  def menu_id
    "ai-credential-menu-#{credential.id}"
  end
end
