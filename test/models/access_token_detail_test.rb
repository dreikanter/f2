require "test_helper"

class AccessTokenDetailTest < ActiveSupport::TestCase
  test "should validate presence of data" do
    detail = build(:access_token_detail, data: nil)
    assert_not detail.valid?
    assert_includes detail.errors[:data], "can't be blank"
  end

  test "#user_info should return user_info hash when data is present" do
    detail = build(:access_token_detail, data: { "user_info" => { "username" => "testuser" } })
    assert_equal({ "username" => "testuser" }, detail.user_info)
  end

  test "#user_info should return empty hash when data is nil" do
    detail = build(:access_token_detail, data: nil)
    assert_equal({}, detail.user_info)
  end

  test "#user_info should return empty hash when user_info key is missing" do
    detail = build(:access_token_detail, data: { "other_key" => "value" })
    assert_equal({}, detail.user_info)
  end

  test "#managed_groups should return managed_groups array when data is present" do
    groups = [{ "username" => "group1" }, { "username" => "group2" }]
    detail = build(:access_token_detail, data: { "managed_groups" => groups })
    assert_equal groups, detail.managed_groups
  end

  test "#managed_groups should return empty array when data is nil" do
    detail = build(:access_token_detail, data: nil)
    assert_equal [], detail.managed_groups
  end

  test "#managed_groups should return empty array when managed_groups key is missing" do
    detail = build(:access_token_detail, data: { "other_key" => "value" })
    assert_equal [], detail.managed_groups
  end
end
