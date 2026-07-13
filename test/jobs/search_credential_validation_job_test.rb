require "test_helper"

class SearchCredentialValidationJobTest < ActiveJob::TestCase
  class FakeProvider
    attr_reader :calls

    def initialize(error: nil)
      @error = error
      @calls = []
    end

    def search(query, max_results:)
      @calls << { query: query, max_results: max_results }
      raise @error if @error

      [WebSearchProvider::Result.new(title: "Ruby", url: "https://ruby-lang.org", snippet: "Ruby")]
    end
  end

  def user
    @user ||= create(:user)
  end

  def credential
    @credential ||= create(:search_credential, user: user, state: :pending, last_error: "old error")
  end

  test "#perform should validate with one result and activate the credential" do
    provider = FakeProvider.new

    WebSearchProvider.stub(:for, provider) do
      SearchCredentialValidationJob.perform_now(credential)
    end

    credential.reload
    assert credential.active?
    assert_not_nil credential.last_validated_at
    assert_nil credential.last_error
    assert_equal [{ query: SearchCredentialValidationJob::VALIDATION_QUERY, max_results: 1 }], provider.calls
  end

  test "#perform should deactivate and record every known provider error type" do
    error_classes = [
      WebSearchProvider::ConfigurationError,
      WebSearchProvider::ProviderError,
      WebSearchProvider::AuthError
    ]

    error_classes.each do |error_class|
      current = create(:search_credential, user: user, state: :pending,
                                           display_name: error_class.name.demodulize)
      provider = FakeProvider.new(error: error_class.new("validation failed"))

      assert_difference("Event.count", 1) do
        WebSearchProvider.stub(:for, provider) do
          SearchCredentialValidationJob.perform_now(current)
        end
      end

      current.reload
      event = Event.where(subject: current, type: "search_credential_deactivated").order(:created_at).last
      assert current.inactive?
      assert_equal "validation failed", current.last_error
      assert_not_nil current.last_validated_at
      assert_not_nil event
      assert_equal "warning", event.level
      assert_equal [{ query: SearchCredentialValidationJob::VALIDATION_QUERY, max_results: 1 }], provider.calls
    end
  end
end
