require "test_helper"

class AccessTokenDetailTest < ActiveSupport::TestCase
  test "#group_names should extract usernames from managed groups" do
    groups = [{ "username" => "group1" }, { "username" => "group2" }, { "id" => "no-name" }]
    detail = build(:access_token_detail, managed_groups: groups)
    assert_equal %w[group1 group2], detail.group_names
  end

  test "#groups_refresh_running? should return false without a refresh state" do
    detail = build(:access_token_detail)
    assert_not detail.groups_refresh_running?
  end

  test "#groups_refresh_running? should return true for a fresh running refresh" do
    detail = create(:access_token_detail)
    detail.begin_groups_refresh!
    assert detail.groups_refresh_running?
  end

  test "#groups_refresh_running? should return false once the refresh goes stale" do
    detail = create(:access_token_detail)
    detail.begin_groups_refresh!

    travel AccessTokenDetail::GROUPS_REFRESH_STALE_AFTER + 1.minute do
      assert_not detail.groups_refresh_running?
    end
  end

  test "#groups_refresh_running? should return false for a running state without a timestamp" do
    detail = build(:access_token_detail, groups_refresh_state: "running", groups_refresh_requested_at: nil)
    assert_not detail.groups_refresh_running?
  end

  test "#groups_refresh_failed? should reflect a failed refresh" do
    detail = create(:access_token_detail)
    assert_not detail.groups_refresh_failed?

    detail.fail_groups_refresh!
    assert detail.groups_refresh_failed?
  end

  test "#begin_groups_refresh! should save a running state on a new record" do
    detail = build(:access_token_detail)
    detail.begin_groups_refresh!

    assert detail.persisted?
    assert detail.groups_refresh_running?
  end

  test "#complete_groups_refresh! should store stringified groups and clear the refresh state" do
    detail = create(:access_token_detail)
    detail.begin_groups_refresh!

    detail.complete_groups_refresh!([{ username: "newgroup", screenName: "New Group" }])

    assert_not detail.groups_refresh_running?
    assert_not detail.groups_refresh_failed?
    assert_equal [{ "username" => "newgroup", "screenName" => "New Group" }], detail.managed_groups
    assert_equal "testuser", detail.reload.freefeed_user_info["username"]
  end

  test "#fail_groups_refresh! should replace a running refresh with a failed one" do
    detail = create(:access_token_detail)
    detail.begin_groups_refresh!

    detail.fail_groups_refresh!

    assert_not detail.groups_refresh_running?
    assert detail.groups_refresh_failed?
  end

  test "should reject an unknown refresh state at the database level" do
    detail = create(:access_token_detail)

    assert_raises ActiveRecord::StatementInvalid do
      detail.update!(groups_refresh_state: "bogus")
    end
  end
end
