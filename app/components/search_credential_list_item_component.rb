class SearchCredentialListItemComponent < CredentialListItemComponent
  private

  def provider_name
    credential.provider_label
  end

  def credential_noun
    "search credential"
  end
end
