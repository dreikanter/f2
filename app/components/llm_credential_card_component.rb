class LlmCredentialCardComponent < ViewComponent::Base
  def initialize(credential:)
    @credential = credential
  end

  private

  attr_reader :credential

  def credential_url
    helpers.llm_credential_path(credential)
  end

  def provider_name
    LlmProvider.find(credential.provider)&.display_name
  end

  def status_label
    credential.state.to_s.capitalize
  end

  def default?
    credential.is_default?
  end

  def inactive?
    credential.inactive?
  end

  def menu_id
    "llm-credential-menu-#{credential.id}"
  end
end
