require "test_helper"

class Onboarding::AccessTokensControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user, :with_onboarding)
  end

  test "should create access token successfully" do
      sign_in_as(user)

      assert_difference "AccessToken.count", 1 do
        post onboarding_access_token_path, params: {
          token: "valid_token_123",
          host: AccessToken::FREEFEED_HOSTS[:production][:url],
          owner: "testuser"
        }
      end

      assert_redirected_to onboarding_feed_path

      access_token = user.access_tokens.last
      assert_equal "testuser at freefeed.net", access_token.name
      assert_equal AccessToken::FREEFEED_HOSTS[:production][:url], access_token.host
      assert_equal "testuser", access_token.owner
      assert_equal "active", access_token.status
      assert_equal "valid_token_123", access_token.token_value

      user.onboarding.reload
      assert_equal access_token.id, user.onboarding.access_token_id
    end

    test "should generate unique token name when name exists" do
      sign_in_as(user)

      # Create existing token with the same base name
      create(:access_token, user: user, name: "testuser at freefeed.net")

      post onboarding_access_token_path, params: {
        token: "valid_token_123",
        host: AccessToken::FREEFEED_HOSTS[:production][:url],
        owner: "testuser"
      }

      access_token = user.access_tokens.last
      assert_equal "testuser at freefeed.net (2)", access_token.name
    end

    test "should generate unique token name with multiple duplicates" do
      sign_in_as(user)

      # Create existing tokens
      create(:access_token, user: user, name: "testuser at freefeed.net")
      create(:access_token, user: user, name: "testuser at freefeed.net (2)")

      post onboarding_access_token_path, params: {
        token: "valid_token_123",
        host: AccessToken::FREEFEED_HOSTS[:production][:url],
        owner: "testuser"
      }

      access_token = user.access_tokens.last
      assert_equal "testuser at freefeed.net (3)", access_token.name
    end

    test "should handle missing token parameter" do
      sign_in_as(user)

      post onboarding_access_token_path, params: {
        host: AccessToken::FREEFEED_HOSTS[:production][:url],
        owner: "testuser"
      }

      assert_response :unprocessable_entity
    end

    test "should handle missing host parameter" do
      sign_in_as(user)

      post onboarding_access_token_path, params: {
        token: "valid_token_123",
        owner: "testuser"
      }

      assert_response :unprocessable_entity
    end

    test "should handle missing owner parameter" do
      sign_in_as(user)

      post onboarding_access_token_path, params: {
        token: "valid_token_123",
        host: AccessToken::FREEFEED_HOSTS[:production][:url]
      }

      assert_response :unprocessable_entity
    end

    test "should require authentication" do
      post onboarding_access_token_path, params: {
        token: "valid_token_123",
        host: AccessToken::FREEFEED_HOSTS[:production][:url],
        owner: "testuser"
      }

      assert_redirected_to new_session_path
    end
end
