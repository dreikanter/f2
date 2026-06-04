class AccessTokenCardComponent < ViewComponent::Base
  def initialize(access_token:)
    @access_token = access_token
  end

  private

  attr_reader :access_token

  def token_url
    helpers.access_token_path(access_token)
  end

  def edit_url
    helpers.edit_access_token_path(access_token)
  end

  def menu_id
    "access-token-menu-#{access_token.id}"
  end

  def delete_modal_id
    "delete-token-modal-#{access_token.id}"
  end

  def owner_label
    if access_token.owner.present?
      "#{access_token.owner}@#{access_token.host_domain}"
    else
      access_token.host_domain
    end
  end

  def status_label
    access_token.status.capitalize
  end
end
