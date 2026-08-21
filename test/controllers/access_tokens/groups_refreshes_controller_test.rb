require "test_helper"

class AccessTokens::GroupsRefreshesControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  def access_token
    @access_token ||= create(:access_token, :active, user: user)
  end

  def detail
    @detail ||= create(:access_token_detail, access_token: access_token,
                       managed_groups: [{ "username" => "oldgroup" }])
  end

  test "#create should require authentication" do
    post access_token_groups_refresh_path(access_token)
    assert_redirected_to new_session_path
  end

  test "#create should start a refresh and render the polling fragment" do
    detail
    sign_in_as user

    assert_enqueued_with(job: TokenGroupsRefreshJob, args: [access_token]) do
      post access_token_groups_refresh_path(access_token)
    end

    assert_response :success
    assert detail.reload.groups_refresh_running?
    assert_match(/turbo-stream.*action="replace".*target="available-groups"/, response.body)
    assert_match(/data-controller="polling"/, response.body)
    assert_match(/access_token\.groups-refreshing/, response.body)
    assert_match(/access_token\.groups-refresh-timeout/, response.body)
  end

  test "#create should not enqueue another job while a refresh is running" do
    detail.begin_groups_refresh!
    sign_in_as user

    assert_no_enqueued_jobs(only: TokenGroupsRefreshJob) do
      post access_token_groups_refresh_path(access_token)
    end

    assert_response :success
    assert_match(/data-controller="polling"/, response.body)
  end

  test "#create should create the detail when the token has none" do
    sign_in_as user

    post access_token_groups_refresh_path(access_token)

    assert_response :success
    assert access_token.reload.access_token_detail.groups_refresh_running?
  end

  test "#create should return not found for another user's token" do
    other_token = create(:access_token, :active, user: create(:user))
    sign_in_as user

    post access_token_groups_refresh_path(other_token)

    assert_response :not_found
  end

  test "#create should refuse a refresh for an inactive token" do
    access_token.inactive!
    sign_in_as user

    assert_no_enqueued_jobs(only: TokenGroupsRefreshJob) do
      post access_token_groups_refresh_path(access_token)
    end

    assert_redirected_to root_path
  end

  test "#show should stay silent while the refresh is running" do
    detail.begin_groups_refresh!
    sign_in_as user

    get access_token_groups_refresh_path(access_token)

    assert_response :no_content
    assert_empty response.body
  end

  test "#show should render the settled groups section once the refresh completes" do
    detail.complete_groups_refresh!([{ "username" => "newgroup" }])
    sign_in_as user

    get access_token_groups_refresh_path(access_token)

    assert_response :success
    assert_match(/target="available-groups"/, response.body)
    assert_match(/newgroup/, response.body)
    assert_match(/access_token\.refresh-groups/, response.body)
    assert_no_match(/data-controller="polling"/, response.body)
  end

  test "#show should surface a failed refresh" do
    detail.fail_groups_refresh!
    sign_in_as user

    get access_token_groups_refresh_path(access_token)

    assert_response :success
    assert_match(/access_token\.groups-refresh-failed/, response.body)
    assert_match(/Couldn't refresh the list/, response.body)
    assert_match(/oldgroup/, response.body)
  end

  test "#show should point at the token when a failed refresh disabled it" do
    detail.fail_groups_refresh!
    access_token.inactive!
    sign_in_as user

    get access_token_groups_refresh_path(access_token)

    assert_response :success
    assert_match(/stopped working/, response.body)
    assert_no_match(/access_token\.refresh-groups/, response.body)
  end

  test "#create should render the selector fragment for the feed form context" do
    detail
    draft = create(:feed, :draft, user: user)
    sign_in_as user

    post access_token_groups_refresh_path(access_token, context: "feed_form", feed_id: draft.id),
         params: { selected: "unsaved-pick" }

    assert_response :success
    assert_match(/target="target-group-selector"/, response.body)
    assert_match(/data-controller="polling"/, response.body)
    assert_match(/context=feed_form/, response.body)
    assert_match(/selected=unsaved-pick/, response.body)
    assert_match(/feed\.groups-refreshing/, response.body)
  end

  test "#show should keep the unsaved selection when re-rendering the selector" do
    detail.complete_groups_refresh!([{ "username" => "alpha" }, { "username" => "beta" }])
    sign_in_as user

    get access_token_groups_refresh_path(access_token, context: "feed_form", selected: "beta")

    assert_response :success
    assert_match(/target="target-group-selector"/, response.body)
    assert_match(/<option selected="selected" value="beta">beta<\/option>/, response.body)
    assert_match(/feed\.refresh-groups/, response.body)
  end

  test "#show should keep a selection that is missing from the refreshed list" do
    detail.complete_groups_refresh!([{ "username" => "alpha" }])
    sign_in_as user

    get access_token_groups_refresh_path(access_token, context: "feed_form", selected: "gone")

    assert_response :success
    assert_match(/<option selected="selected" value="gone">gone<\/option>/, response.body)
    assert_match(/alpha/, response.body)
  end

  test "#show should blame the fetch when a failed refresh leaves no groups" do
    @detail = create(:access_token_detail, access_token: access_token)
    @detail.fail_groups_refresh!
    sign_in_as user

    get access_token_groups_refresh_path(access_token, context: "feed_form")

    assert_response :success
    assert_match(/Could not load groups/, response.body)
    assert_no_match(/doesn't manage any groups yet/, response.body)
  end
end
