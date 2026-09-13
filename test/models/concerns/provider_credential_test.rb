require "test_helper"

class ProviderCredentialTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  [:ai_credential, :search_credential].each do |factory|
    test "#validate_async should preserve #{factory} usability during revalidation" do
      credential = create(factory, :active)
      job = factory == :ai_credential ? AiCredentialValidationJob : SearchCredentialValidationJob

      run = credential.validate_async(job)

      assert_predicate credential.reload, :active?
      assert_predicate credential, :validation_in_progress?
      assert_empty run.context
    end

    test "#update should invalidate #{factory} data and obsolete work without rejection side effects" do
      credential = create(factory, :active)
      feed = create(:feed, :enabled, user: credential.user, factory => credential)
      validation = OperationRun.start!(subject: credential, kind: :validation)
      refresh = OperationRun.start!(subject: credential, kind: :models_refresh)
      completed = create(:operation_run, subject: credential, kind: :validation, status: :failed, finished_at: 1.hour.ago)
      original_outcome = completed.attributes

      assert_no_difference "Event.count" do
        credential.update!(credential_data: { "api_key" => "replacement-key" })
      end

      assert_not_predicate credential.reload, :active?
      assert_not credential.class.active.exists?(credential.id)
      assert_predicate feed.reload, :enabled?
      assert_predicate validation.reload, :superseded?
      assert_predicate refresh.reload, :superseded?
      assert_equal original_outcome, completed.reload.attributes
      assert_not credential.validation_in_progress?
    end

    test "#update should retain #{factory} usability and running checks for name and unchanged data edits" do
      credential = create(factory, :active)
      run = OperationRun.start!(subject: credential, kind: :validation)

      credential.update!(display_name: "Renamed", credential_data: credential.credential_data.deep_dup)

      assert_predicate credential.reload, :active?
      assert_predicate run.reload, :running?
      assert_predicate credential, :validation_in_progress?
    end
  end
end
