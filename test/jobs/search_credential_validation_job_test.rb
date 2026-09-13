require "test_helper"

class SearchCredentialValidationJobTest < ActiveJob::TestCase
  class FakeProvider
    attr_reader :calls

    def initialize(error: nil, &before_response)
      @error = error
      @before_response = before_response
      @calls = []
    end

    def search(query, max_results:)
      @calls << { query: query, max_results: max_results }
      @before_response&.call
      raise @error if @error

      [WebSearchProvider::Result.new(title: "Ruby", url: "https://ruby-lang.org", snippet: "Ruby")]
    end
  end

  def user
    @user ||= create(:user)
  end

  def credential
    @credential ||= create(:search_credential, user: user, active: false, last_error: "old error")
  end

  def perform_validation(current = credential)
    run = current.validate_async(SearchCredentialValidationJob)
    SearchCredentialValidationJob.perform_now(run)
    run
  end

  test "#perform should validate with one result, record usage, and activate the credential" do
    provider = FakeProvider.new

    assert_difference("Event.where(type: WebSearchUsage::EVENT_TYPE).count", 1) do
      WebSearchProvider.stub(:for, provider) do
        perform_validation
      end
    end

    credential.reload
    search_event = Event.where(type: WebSearchUsage::EVENT_TYPE, subject: credential).sole
    assert credential.active?
    assert_not_nil credential.last_validated_at
    assert_nil credential.last_error
    assert_empty search_event.incoming_event_references
    assert_equal [{ query: SearchCredentialValidationJob::VALIDATION_QUERY, max_results: 1 }], provider.calls
  end

  [WebSearchProvider::AuthError, WebSearchProvider::ProviderError].each do |error_class|
    test "#perform should record usage and deactivate on #{error_class.name.demodulize}" do
      current = create(:search_credential, :active, user: user)
      provider = FakeProvider.new(error: error_class.new("validation failed"))

      assert_difference("Event.count", 2) do
        WebSearchProvider.stub(:for, provider) do
          perform_validation(current)
        end
      end

      current.reload
      search_event = Event.where(subject: current, type: WebSearchUsage::EVENT_TYPE).sole
      deactivation_event = Event.where(subject: current, type: "search_credential_deactivated").sole
      assert_not current.active?
      assert_equal "validation failed", current.last_error
      assert_not_nil current.last_validated_at
      assert_empty search_event.incoming_event_references
      assert_equal "warning", deactivation_event.level
      assert_equal [{ query: SearchCredentialValidationJob::VALIDATION_QUERY, max_results: 1 }], provider.calls
    end
  end

  test "#perform should still activate the credential when usage recording breaks" do
    provider = FakeProvider.new
    failing = ->(**) { raise ActiveRecord::RecordInvalid }

    WebSearchUsage.stub(:record!, failing) do
      WebSearchProvider.stub(:for, provider) do
        perform_validation
      end
    end

    assert credential.reload.active?
  end

  test "#perform should not let a superseded run make a billed request" do
    stale_run = credential.validate_async(SearchCredentialValidationJob)
    current_run = credential.validate_async(SearchCredentialValidationJob)
    provider = FakeProvider.new

    WebSearchProvider.stub(:for, provider) do
      SearchCredentialValidationJob.perform_now(stale_run)
    end

    assert_empty provider.calls
    assert_not credential.reload.active?
    assert_predicate current_run.reload, :running?
  end

  { success: nil, rejection: WebSearchProvider::AuthError.new("invalid key") }.each do |outcome, error|
    test "#perform should discard #{outcome} after credential replacement" do
      current = create(:search_credential, :active)
      run = current.validate_async(SearchCredentialValidationJob)
      replacement_run = nil
      provider = FakeProvider.new(error: error) do
        replacement = SearchCredential.find(current.id)
        replacement.update!(credential_data: { "api_key" => "replacement-key" })
        replacement_run = replacement.validate_async(SearchCredentialValidationJob)
      end

      WebSearchProvider.stub(:for, provider) do
        SearchCredentialValidationJob.perform_now(run)
      end

      assert_predicate run.reload, :superseded?
      assert_predicate replacement_run.reload, :running?
      assert_not_predicate current.reload, :active?
      assert_nil current.last_error
      assert_not Event.exists?(subject: current, type: "search_credential_deactivated")
    end

    test "#perform should preserve usability on #{outcome} received after the deadline" do
      current = create(:search_credential, :active)
      run = current.validate_async(SearchCredentialValidationJob)
      provider = FakeProvider.new(error: error) { travel_to run.deadline_at + 1.second }

      WebSearchProvider.stub(:for, provider) { SearchCredentialValidationJob.perform_now(run) }

      assert_predicate run.reload, :timed_out?
      assert_predicate current.reload, :active?
      assert_not Event.exists?(subject: current, type: "search_credential_deactivated")
    end
  end

  test "#perform should avoid a billed request after the deadline" do
    run = credential.validate_async(SearchCredentialValidationJob)
    provider = FakeProvider.new

    travel_to run.deadline_at + 1.second do
      WebSearchProvider.stub(:for, provider) { SearchCredentialValidationJob.perform_now(run) }
    end

    assert_empty provider.calls
    assert_predicate run.reload, :timed_out?
    assert_not_predicate credential.reload, :active?
  end
end
