require "test_helper"

class AccessTokenDetailTest < ActiveSupport::TestCase
  def detail
    @detail ||= create(:access_token_detail)
  end

  test "#expired? should return true when expires_at is in the past" do
    expired_detail = build(:access_token_detail, expires_at: 1.hour.ago)
    assert expired_detail.expired?
  end

  test "#expired? should return false when expires_at is in the future" do
    assert_not detail.expired?
  end

  test "should validate presence of data" do
    detail = build(:access_token_detail, data: nil)
    assert_not detail.valid?
    assert_includes detail.errors[:data], "can't be blank"
  end

  test "should validate presence of expires_at" do
    detail = build(:access_token_detail, expires_at: nil)
    assert_not detail.valid?
    assert_includes detail.errors[:expires_at], "can't be blank"
  end

  test ".expired scope should return expired details" do
    expired = create(:access_token_detail, expires_at: 1.hour.ago)
    valid = create(:access_token_detail, expires_at: 1.hour.from_now)

    expired_details = AccessTokenDetail.expired
    assert_includes expired_details, expired
    assert_not_includes expired_details, valid
  end

  test ".valid scope should return non-expired details" do
    expired = create(:access_token_detail, expires_at: 1.hour.ago)
    valid = create(:access_token_detail, expires_at: 1.hour.from_now)

    valid_details = AccessTokenDetail.valid
    assert_includes valid_details, valid
    assert_not_includes valid_details, expired
  end

  test "TTL constant should be 24 hours" do
    assert_equal 24.hours, AccessTokenDetail::TTL
  end
end
