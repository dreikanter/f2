require "test_helper"
require "rake"

class AiVerifyExtractionTest < ActiveSupport::TestCase
  setup do
    Feeder::Application.load_tasks unless Rake::Task.task_defined?("ai:verify_extraction")
    @task = Rake::Task["ai:verify_extraction"]
    @task.reenable
  end

  def with_env(values)
    original = values.keys.index_with { |key| ENV.fetch(key, nil) }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    original.each { |key, value| ENV[key] = value }
  end

  # The task drives a live provider, so the reachable behavior here is its
  # refusal to start: an unset or unknown id must name what to set rather than
  # fail somewhere inside the call.
  test "ai:verify_extraction should skip when AI_CREDENTIAL_ID names no credential" do
    with_env("AI_CREDENTIAL_ID" => nil, "SEARCH_CREDENTIAL_ID" => nil) do
      out, = capture_io { @task.invoke }

      assert_match(/SKIP: set AI_CREDENTIAL_ID/, out)
    end
  end

  test "ai:verify_extraction should skip when the credential belongs to another provider" do
    credential = create(:ai_credential, provider: "openrouter")

    with_env("AI_CREDENTIAL_ID" => credential.id, "SEARCH_CREDENTIAL_ID" => nil) do
      out, = capture_io { @task.invoke }

      assert_match(/SKIP: set AI_CREDENTIAL_ID/, out)
    end
  end

  test "ai:verify_extraction should skip when no active search credential is named" do
    credential = create(:ai_credential, provider: "anthropic")

    with_env("AI_CREDENTIAL_ID" => credential.id, "SEARCH_CREDENTIAL_ID" => nil) do
      out, = capture_io { @task.invoke }

      assert_match(/SKIP: set SEARCH_CREDENTIAL_ID/, out)
    end
  end
end
