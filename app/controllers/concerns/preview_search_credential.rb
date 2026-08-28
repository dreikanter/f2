# An AI preview run needs a search credential, and the choice isn't stored on the
# preview row, so the create and refresh paths both resolve it from the user.
module PreviewSearchCredential
  extend ActiveSupport::Concern

  private

  # @param profile_key [String] the preview's profile
  # @param requested_id [String, nil] a credential chosen in the form
  # @return [SearchCredential, nil] the credential backing the run
  def resolve_search_credential(profile_key, requested_id = nil)
    return unless FeedProfile.exists?(profile_key) && FeedProfile.depends_on_ai?(profile_key)

    credentials = Current.user.search_credentials.active
    return credentials.find_by(id: requested_id) if requested_id.present?

    credentials.find_by(id: Current.user.default_search_credential_id) || credentials.first
  end
end
