# Checks provider authentication and settles the credential's validation run.
class AiCredentialValidation
  # @param run [OperationRun] validation being performed
  def initialize(run)
    @run = run
  end

  def call
    return unless run.reload.running?
    return run.timeout! if run.deadline_reached?

    original_data = credential.credential_data.deep_dup
    credential.build_llm_client.validate_credentials!

    with_current_credential(original_data) do
      run.succeed! do |credential|
        credential.update!(active: true, last_validated_at: Time.current, last_error: nil)
      end
    end
  rescue LlmProvider::Error => error
    Rails.error.report(error, context: { credential_id: credential.id })
    with_current_credential(original_data) { fail_validation(error) }
  end

  private

  attr_reader :run

  def credential
    run.subject
  end

  def with_current_credential(original_data)
    credential.with_lock do
      return run.supersede! unless credential.credential_data == original_data
      return run.timeout! if run.deadline_reached?

      yield
    end
  end

  def fail_validation(error)
    run.fail! do |credential|
      run.update!(context: run.context.merge(error.details))
      if error.invalid_key?
        credential.deactivate!(last_error: error.message)
      else
        credential.update!(last_error: error.message)
      end
    end
  end
end
