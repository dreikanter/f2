require "test_helper"

class LlmCapabilityProbeTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:content)

  class FakeChat
    def initialize(response)
      @response = response
    end

    def with_schema(_schema) = self
    def with_params(**) = self

    def ask(_prompt)
      raise @response if @response.is_a?(StandardError)

      FakeResponse.new(@response)
    end
  end

  class FakeProvider
    attr_reader :key

    def initialize(responses, fetch_params: nil)
      @responses = responses.is_a?(Array) ? responses.dup : [responses]
      @fetch_params = fetch_params
      @key = "fake"
    end

    def chat(_model) = FakeChat.new(@responses.shift)
    def prepare_web(_chat) = nil
    def web_params(_model) = { tools: [] }
    def web_search_params(_model) = { tools: [] }
    def web_fetch_params(_model) = @fetch_params
  end

  def run_checks(responses, checks, fetch_params: nil)
    provider = FakeProvider.new(responses, fetch_params: fetch_params)
    LlmCapabilityProbe::Runner.new(provider: provider, model: "test-model", checks: checks).run
  end

  def valid_payload
    { "items" => [{ "uid" => "u1", "body" => "b", "source_url" => "https://example.com/p" }] }
  end

  test "#run should pass the plain check on a pong reply" do
    outcome = run_checks("pong", ["plain"])

    assert outcome[:passed]
    assert_equal "PASS", outcome[:results].first[:status]
  end

  test "#run should fail the plain check on an unexpected reply" do
    outcome = run_checks("hello", ["plain"])

    assert_not outcome[:passed]
    assert_equal "FAIL", outcome[:results].first[:status]
  end

  test "#run should pass the schema check on schema-valid items" do
    outcome = run_checks(valid_payload, ["schema"])

    assert_equal "PASS", outcome[:results].first[:status]
    assert_match(/1 items/, outcome[:results].first[:note])
  end

  test "#run should fail the schema check on a schema violation" do
    payload = { "items" => [{ "uid" => "u1", "body" => "b", "source_url" => "x", "extra" => 1 }] }
    outcome = run_checks(payload, ["schema"])

    assert_equal "FAIL", outcome[:results].first[:status]
    assert_match(/schema violation/, outcome[:results].first[:note])
  end

  test "#run should fail the schema check on empty items" do
    outcome = run_checks({ "items" => [] }, ["schema"])

    assert_equal "FAIL", outcome[:results].first[:status]
    assert_match(/empty items/, outcome[:results].first[:note])
  end

  test "#run should fail the schema check on a non-JSON reply" do
    outcome = run_checks("not json at all", ["schema"])

    assert_equal "FAIL", outcome[:results].first[:status]
    assert_match(/non-JSON/, outcome[:results].first[:note])
  end

  test "#run should pass the web search check on grounded output with URLs" do
    text = "Latest posts: https://example.com/a — release notes. #{'x' * 80}"
    outcome = run_checks(text, ["web_search"])

    assert_equal "PASS", outcome[:results].first[:status]
  end

  test "#run should fail the web search check without URLs" do
    outcome = run_checks("no links here #{'x' * 80}", ["web_search"])

    assert_equal "FAIL", outcome[:results].first[:status]
  end

  test "#run should fail the web search check on a refusal that contains URLs" do
    refusal = "I don't have the ability to browse the live web. Visit https://rubyonrails.org/blog " \
              "or subscribe to https://rubyonrails.org/feed.xml for updates."
    outcome = run_checks(refusal, ["web_search"])

    assert_equal "FAIL", outcome[:results].first[:status]
    assert_equal "model reports no web access", outcome[:results].first[:note]
  end

  test "#run should skip the web fetch check when the provider has no mechanism" do
    outcome = run_checks([], ["web_fetch"])

    assert_equal "SKIP", outcome[:results].first[:status]
    assert outcome[:passed]
  end

  test "#run should pass the web fetch check when page content is quoted" do
    outcome = run_checks("The heading says: Example Domain", ["web_fetch"], fetch_params: { tools: [] })

    assert_equal "PASS", outcome[:results].first[:status]
  end

  test "#run should fail two_step when gather returns blank" do
    outcome = run_checks("   ", ["two_step"])

    assert_equal "FAIL", outcome[:results].first[:status]
    assert_match(/gather returned blank/, outcome[:results].first[:note])
  end

  test "#run should pass two_step when gather feeds a schema-valid structure step" do
    outcome = run_checks(["gathered post text https://example.com/p", valid_payload], ["two_step"])

    assert_equal "PASS", outcome[:results].first[:status]
    assert_equal "https://example.com/p", outcome[:results].first[:evidence][:items].first["source_url"]
  end

  test "#run should record an exception as a failed check" do
    outcome = run_checks(RuntimeError.new("boom"), ["plain"])

    assert_equal "FAIL", outcome[:results].first[:status]
    assert_match(/RuntimeError: boom/, outcome[:results].first[:note])
  end

  test ".build should raise on an unknown provider" do
    error = assert_raises(ArgumentError) { LlmCapabilityProbe::Provider.build("nope") }
    assert_match(/Unknown provider/, error.message)
  end

  test ".configured? should reflect presence of the provider env key" do
    original = ENV.fetch("MOONSHOT_API_KEY", nil)
    ENV["MOONSHOT_API_KEY"] = nil
    assert_not LlmCapabilityProbe::Provider.configured?("moonshot")

    ENV["MOONSHOT_API_KEY"] = "k"
    assert LlmCapabilityProbe::Provider.configured?("moonshot")
    assert_not LlmCapabilityProbe::Provider.configured?("nope")
  ensure
    ENV["MOONSHOT_API_KEY"] = original
  end

  test "provider web params should declare the production tool shapes" do
    anthropic = LlmCapabilityProbe::Provider.build("anthropic")
    assert_equal %w[web_search web_fetch], anthropic.web_params("m")[:tools].map { |t| t[:name] }
    assert_equal 1, anthropic.web_search_params("m")[:tools].size
    assert_equal "web_fetch_20260209", anthropic.web_fetch_params("m")[:tools].first[:type]

    moonshot = LlmCapabilityProbe::Provider.build("moonshot")
    assert_equal "$web_search", moonshot.web_params("m")[:tools].first[:function][:name]
    assert_nil moonshot.web_fetch_params("m")
  end

  test "moonshot echo tool should return its arguments verbatim" do
    tool = LlmCapabilityProbe::MoonshotWebSearchEcho.new
    assert_equal "$web_search", tool.name
    assert_equal({ query: "ruby" }, tool.execute(query: "ruby"))
  end
end
