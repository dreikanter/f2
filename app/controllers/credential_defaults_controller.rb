# Promotes one of the user's credentials to be their default for that provider
# type. The list re-renders in place over Turbo, or falls back to a redirect.
#
# Subclasses declare their model and the noun used in the confirmation; the
# nested param and the list path follow from the model.
class CredentialDefaultsController < ApplicationController
  class_attribute :credential_class, instance_writer: false

  def update
    authorize credential, :update?
    credential.make_default!

    respond_to do |format|
      format.turbo_stream do
        flash.now[:success] = success_message
        @credentials = scope.order(created_at: :desc)
      end
      format.html do
        redirect_to helpers.polymorphic_path(credential_class), success: success_message
      end
    end
  end

  private

  # Completes "'<name>' is now the default …". The AI wording omits the type,
  # which is why this is a subclass hook rather than something derived.
  def credential_noun
    raise NotImplementedError, "#{self.class.name} must implement #credential_noun"
  end

  def success_message
    "'#{credential.display_name}' is now the default #{credential_noun}."
  end

  def credential
    @credential ||= scope.find(params[:"#{credential_class.model_name.param_key}_id"])
  end

  def scope
    policy_scope(credential_class)
  end
end
