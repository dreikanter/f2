require "test_helper"

class Onboarding::ValidationsControllerTest < ActionDispatch::IntegrationTest
    def user
      @user ||= create(:user, :with_onboarding)
    end

    test "should validate token successfully" do
      sign_in_as(user)

      # Mock FreefeedClient
      mock_client = Minitest::Mock.new
      mock_client.expect :whoami, { id: "user123", username: "testuser", screen_name: "Test User", email: "test@example.com" }
      mock_client.expect :managed_groups, [
        { id: "group1", username: "testgroup", screen_name: "Test Group", is_private: false, is_restricted: false }
      ]

      FreefeedClient.stub :new, mock_client do
        post onboarding_validation_path, params: {
          token: "valid_token",
          host: AccessToken::FREEFEED_HOSTS["production"][:url]
        }
      end

      assert_response :success
      assert_match "testuser", response.body
      mock_client.verify
    end

    test "should handle invalid token" do
      sign_in_as(user)

      FreefeedClient.stub :new, ->(*) { raise FreefeedClient::UnauthorizedError, "Invalid token" } do
        post onboarding_validation_path, params: {
          token: "invalid_token",
          host: AccessToken::FREEFEED_HOSTS["production"][:url]
        }
      end

      assert_response :unprocessable_entity
      assert_match "Invalid token or insufficient permissions", response.body
    end

    test "should handle missing token parameter" do
      sign_in_as(user)

      post onboarding_validation_path, params: {
        host: AccessToken::FREEFEED_HOSTS["production"][:url]
      }

      assert_response :bad_request
    end

    test "should handle missing host parameter" do
      sign_in_as(user)

      post onboarding_validation_path, params: {
        token: "valid_token"
      }

      assert_response :bad_request
    end

    test "should require authentication" do
      post onboarding_validation_path, params: {
        token: "valid_token",
        host: AccessToken::FREEFEED_HOSTS["production"][:url]
      }

      assert_redirected_to new_session_path
    end

    test "should handle FreefeedClient errors" do
      sign_in_as(user)

      FreefeedClient.stub :new, ->(*) { raise FreefeedClient::Error, "API error" } do
        post onboarding_validation_path, params: {
          token: "valid_token",
          host: AccessToken::FREEFEED_HOSTS["production"][:url]
        }
      end

      assert_response :unprocessable_entity
      assert_match "Failed to validate token", response.body
    end
end
