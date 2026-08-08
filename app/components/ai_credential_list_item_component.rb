class AiCredentialListItemComponent < CredentialListItemComponent
  private

  def provider_name
    credential.llm_provider.display_name
  end

  def credential_noun
    "AI credential"
  end
end
