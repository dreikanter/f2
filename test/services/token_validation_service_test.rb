require "test_helper"

class TokenValidationServiceTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  def active_token
    @active_token ||= create(:access_token, user: user)
  end

  def inactive_token
    @inactive_token ||= create(:access_token, :inactive, user: user)
  end

  test "validates active token and returns user" do
    token_value = active_token.token
    result = TokenValidationService.validate_token(token_value)
    assert_equal user, result
  end

  test "updates last_used_at when validating token" do
    token_value = active_token.token
    assert_nil active_token.last_used_at

    TokenValidationService.validate_token(token_value)

    assert_not_nil active_token.reload.last_used_at
  end

  test "returns false for invalid token" do
    result = TokenValidationService.validate_token("invalid_token")
    assert_equal false, result
  end

  test "returns false for blank token" do
    result = TokenValidationService.validate_token("")
    assert_equal false, result

    result = TokenValidationService.validate_token(nil)
    assert_equal false, result
  end

  test "returns false for inactive token" do
    token_value = inactive_token.token
    result = TokenValidationService.validate_token(token_value)
    assert_equal false, result
  end

  test "does not update last_used_at for inactive token" do
    token_value = inactive_token.token
    original_last_used = inactive_token.last_used_at

    TokenValidationService.validate_token(token_value)

    assert_equal original_last_used, inactive_token.reload.last_used_at
  end
end
