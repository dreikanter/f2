class AccessTokenValidationTimeoutJob < ApplicationJob
  queue_as :timeouts

  # @param run [OperationRun] validation being timed out
  def perform(run)
    run.timeout! do |access_token|
      access_token.update!(state: :inactive)
      Event.create!(
        type: AccessToken::VALIDATION_ABANDONED_EVENT_TYPE,
        user: access_token.user,
        subject: access_token,
        level: :warning
      )
    end
  end
end
