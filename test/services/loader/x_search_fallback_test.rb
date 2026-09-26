require "test_helper"

class Loader::XSearchFallbackTest < ActiveSupport::TestCase
  POST_ID = "2103847338905088489"
  POST_URL = "https://x.com/TechCrunch/status/#{POST_ID}"

  test "#candidates should inspect recent posts from native search source accounts" do
    stub_profile
    stub_post

    travel_to Time.iso8601("2026-09-26T19:00:00Z") do
      candidates = Loader::XSearchFallback.new(chat).candidates

      assert_equal 1, candidates.size
      assert_equal POST_URL, candidates.sole.fetch(:source_url)
      assert_equal "2026-09-26T14:01:07.000Z", candidates.sole.fetch(:published_at)
      assert_equal "2026-09-26T19:00:00Z", candidates.sole.fetch(:retrieved_at)
      assert_equal "An AI avatar prompts mixed feelings.", candidates.sole.fetch(:excerpt)
    end
  end

  test "#candidates should reject a source date inconsistent with the X post ID" do
    stub_profile
    stub_post(published_at: "2026-09-25T14:01:07.000Z")

    assert_empty Loader::XSearchFallback.new(chat).candidates
  end

  test "#candidates should not fetch accounts absent from native search sources" do
    unrelated_chat = fake_chat("https://example.com/TechCrunch")

    assert_empty Loader::XSearchFallback.new(unrelated_chat).candidates
    assert_not_requested :get, /x\.com/
  end

  private

  def chat
    @chat ||= fake_chat("https://x.com/TechCrunch/status/2102800000000000000")
  end

  def fake_chat(source_url)
    call = Struct.new(:input).new({ sources: [{ url: source_url }] })
    message = Struct.new(:server_tool_calls).new([call])
    Struct.new(:started_at, :deadline_at, :messages).new(
      Time.iso8601("2026-09-26T19:00:00Z"), 2.minutes.from_now, [message]
    )
  end

  def stub_profile
    stub_request(:get, "https://x.com/TechCrunch").to_return(
      body: %(<article><a href="/TechCrunch/status/#{POST_ID}">post</a></article>)
    )
  end

  def stub_post(published_at: "2026-09-26T14:01:07.000Z")
    stub_request(:get, "https://x.com/i/status/#{POST_ID}")
      .to_return(status: 307, headers: { "Location" => "/TechCrunch/status/#{POST_ID}" })
    stub_request(:get, POST_URL).to_return(body: <<~HTML)
      <html><head>
      <meta property="og:url" content="#{POST_URL}">
      <meta property="article:published_time" content="#{published_at}">
      <meta property="og:description" content="An AI avatar prompts mixed feelings.">
      </head></html>
    HTML
  end
end
