class CredentialDeleteModalComponent < ViewComponent::Base
  def initialize(credential:)
    @credential = credential
  end

  def self.modal_id(credential)
    "delete-#{credential.model_name.param_key.dasherize}-modal-#{credential.id}"
  end

  private

  attr_reader :credential

  def modal_id
    self.class.modal_id(credential)
  end

  def credential_type
    credential.model_name.human
  end
end
