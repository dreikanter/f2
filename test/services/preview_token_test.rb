require "test_helper"

class PreviewTokenTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  def base_args
    {
      user_id: user.id,
      profile_key: "rss",
      params: { "url" => "https://example.com/feed.xml" },
      generated_at: Time.current
    }
  end

  test ".sign should return a string token" do
    token = PreviewToken.sign(**base_args)

    assert_kind_of String, token
    assert_not token.empty?
  end

  test ".sign should produce identical tokens for identical input" do
    token1 = PreviewToken.sign(**base_args)
    token2 = PreviewToken.sign(**base_args)

    assert_equal token1, token2
  end

  test ".sign should produce different tokens when params differ" do
    token1 = PreviewToken.sign(**base_args)
    token2 = PreviewToken.sign(**base_args.merge(params: { "url" => "https://other.example/feed.xml" }))

    assert_not_equal token1, token2
  end

  test ".sign should produce different tokens when params keys are reordered" do
    # Params with same content but different key insertion order should
    # produce the same token (digest is stable).
    args_a = base_args.merge(params: { "a" => 1, "b" => 2 })
    args_b = base_args.merge(params: { "b" => 2, "a" => 1 })

    assert_equal PreviewToken.sign(**args_a), PreviewToken.sign(**args_b)
  end

  test ".verify should accept a valid token for matching args" do
    token = PreviewToken.sign(**base_args)

    assert PreviewToken.verify(
      token,
      user_id: user.id,
      profile_key: "rss",
      params: { "url" => "https://example.com/feed.xml" }
    )
  end

  test ".verify should reject a tampered token" do
    token = PreviewToken.sign(**base_args)
    tampered = token.reverse

    assert_not PreviewToken.verify(
      tampered,
      user_id: user.id,
      profile_key: "rss",
      params: { "url" => "https://example.com/feed.xml" }
    )
  end

  test ".verify should reject when user_id differs" do
    token = PreviewToken.sign(**base_args)

    assert_not PreviewToken.verify(
      token,
      user_id: user.id + 1,
      profile_key: "rss",
      params: { "url" => "https://example.com/feed.xml" }
    )
  end

  test ".verify should reject when profile_key differs" do
    token = PreviewToken.sign(**base_args)

    assert_not PreviewToken.verify(
      token,
      user_id: user.id,
      profile_key: "xkcd",
      params: { "url" => "https://example.com/feed.xml" }
    )
  end

  test ".verify should reject when params differ" do
    token = PreviewToken.sign(**base_args)

    assert_not PreviewToken.verify(
      token,
      user_id: user.id,
      profile_key: "rss",
      params: { "url" => "https://different.example/feed.xml" }
    )
  end

  test ".verify should reject an expired token" do
    travel_to Time.utc(2026, 5, 16, 12, 0, 0) do
      @token = PreviewToken.sign(**base_args)
    end

    travel_to Time.utc(2026, 5, 16, 13, 0, 1) do
      assert_not PreviewToken.verify(
        @token,
        user_id: user.id,
        profile_key: "rss",
        params: { "url" => "https://example.com/feed.xml" }
      )
    end
  end

  test ".verify should accept a token at the edge of the 60-minute window" do
    travel_to Time.utc(2026, 5, 16, 12, 0, 0) do
      @token = PreviewToken.sign(**base_args)
    end

    travel_to Time.utc(2026, 5, 16, 12, 59, 59) do
      assert PreviewToken.verify(
        @token,
        user_id: user.id,
        profile_key: "rss",
        params: { "url" => "https://example.com/feed.xml" }
      )
    end
  end

  test ".verify should reject a blank token" do
    assert_not PreviewToken.verify("", user_id: user.id, profile_key: "rss", params: {})
    assert_not PreviewToken.verify(nil, user_id: user.id, profile_key: "rss", params: {})
  end

  test ".verify should reject a malformed token" do
    assert_not PreviewToken.verify("not-a-token", user_id: user.id, profile_key: "rss", params: {})
    assert_not PreviewToken.verify("aGVsbG8=.aGVsbG8=", user_id: user.id, profile_key: "rss", params: {})
  end
end
