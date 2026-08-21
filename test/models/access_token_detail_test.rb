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

  test "#group_names should extract usernames from managed groups" do
    groups = [{ "username" => "group1" }, { "username" => "group2" }, { "id" => "no-name" }]
    detail = build(:access_token_detail, data: { "managed_groups" => groups })
    assert_equal %w[group1 group2], detail.group_names
  end

  test "#groups_refresh_running? should return false without a marker" do
    detail = build(:access_token_detail)
    assert_not detail.groups_refresh_running?
  end

  test "#groups_refresh_running? should return true for a fresh running marker" do
    detail = create(:access_token_detail)
    detail.begin_groups_refresh!
    assert detail.groups_refresh_running?
  end

  test "#groups_refresh_running? should return false once the marker goes stale" do
    detail = create(:access_token_detail)
    detail.begin_groups_refresh!

    travel AccessTokenDetail::GROUPS_REFRESH_STALE_AFTER + 1.minute do
      assert_not detail.groups_refresh_running?
    end
  end

  test "#groups_refresh_running? should return false for an unparsable timestamp" do
    detail = build(:access_token_detail, data: { "groups_refresh" => { "state" => "running", "requested_at" => "bogus" } })
    assert_not detail.groups_refresh_running?
  end

  test "#groups_refresh_failed? should reflect a failed marker" do
    detail = create(:access_token_detail)
    assert_not detail.groups_refresh_failed?

    detail.fail_groups_refresh!
    assert detail.groups_refresh_failed?
  end

  test "#begin_groups_refresh! should save a running marker on a new record" do
    detail = build(:access_token_detail, data: nil)
    refresh_id = detail.begin_groups_refresh!

    assert detail.persisted?
    assert detail.groups_refresh_running?
    assert refresh_id.present?
  end

  test "#complete_groups_refresh! should keep a newer marker but store the groups" do
    detail = create(:access_token_detail)
    stale_id = detail.begin_groups_refresh!
    detail.begin_groups_refresh!

    detail.complete_groups_refresh!([{ username: "newgroup" }], stale_id)

    assert detail.groups_refresh_running?
    assert_equal ["newgroup"], detail.group_names
  end

  test "#fail_groups_refresh! should not touch a newer marker" do
    detail = create(:access_token_detail)
    stale_id = detail.begin_groups_refresh!
    detail.begin_groups_refresh!

    detail.fail_groups_refresh!(stale_id)

    assert detail.groups_refresh_running?
    assert_not detail.groups_refresh_failed?
  end

  test "#complete_groups_refresh! should store stringified groups and clear the marker" do
    detail = create(:access_token_detail)
    detail.begin_groups_refresh!

    detail.complete_groups_refresh!([{ username: "newgroup", screenName: "New Group" }])

    assert_not detail.groups_refresh_running?
    assert_not detail.groups_refresh_failed?
    assert_equal [{ "username" => "newgroup", "screenName" => "New Group" }], detail.managed_groups
    assert_equal({ "username" => "testuser", "screen_name" => "Test User" }, detail.reload.user_info)
  end

  test "#fail_groups_refresh! should replace a running marker with a failed one" do
    detail = create(:access_token_detail)
    detail.begin_groups_refresh!

    detail.fail_groups_refresh!

    assert_not detail.groups_refresh_running?
    assert detail.groups_refresh_failed?
  end
end
