# On-demand refresh of a token's postable groups. `create` marks the refresh
# running and enqueues the background fetch; `show` is the polling endpoint
# that stays silent while the job runs and answers with the re-rendered
# fragment once it settles. Which fragment depends on where the refresh was
# requested: the token page's Available Groups section, or the feed form's
# target-group selector (context=feed_form).
class AccessTokens::GroupsRefreshesController < ApplicationController
  include StatePolling

  def create
    authorize access_token, :refresh?

    unless detail.groups_refresh_running?
      refresh_id = detail.begin_groups_refresh!
      TokenGroupsRefreshJob.perform_later(access_token, refresh_id)
    end

    render_fragment(refreshing: true)
  end

  def show
    authorize access_token, :show?

    return head :no_content if access_token.access_token_detail&.groups_refresh_running?

    render_fragment(refreshing: false)
  end

  private

  def access_token
    @access_token ||= policy_scope(AccessToken).find(params[:access_token_id])
  end

  def detail
    @detail ||= access_token.access_token_detail || access_token.build_access_token_detail
  end

  def render_fragment(refreshing:)
    failed = !refreshing && !!access_token.access_token_detail&.groups_refresh_failed?

    if params[:context] == "feed_form"
      render turbo_stream: turbo_stream.replace(
        "target-group-selector",
        partial: "feeds/target_group_selector",
        locals: selector_locals(refreshing: refreshing, failed: failed)
      )
    else
      render turbo_stream: turbo_stream.replace(
        "available-groups",
        partial: "access_tokens/available_groups",
        locals: { access_token: access_token, refreshing: refreshing, refresh_failed: failed }
      )
    end
  end

  # Mirrors AccessTokens::GroupsController's selector rendering, but reads the
  # persisted group list (the refresh job's output) instead of fetching live,
  # and threads the form's unsaved selection through so the replace doesn't
  # reset it.
  def selector_locals(refreshing:, failed:)
    groups = detail.group_names.sort

    {
      feed: feed,
      token: access_token,
      groups: groups,
      token_error: empty_groups_error(groups, failed),
      selected: params[:selected].presence,
      refreshing: refreshing,
      refresh_failed: failed
    }
  end

  # With nothing to list, the selector's message should blame the failed fetch
  # rather than declare the account group-less.
  def empty_groups_error(groups, failed)
    return unless groups.empty? && access_token.active?

    failed ? :api_error : :empty
  end

  def feed
    @feed ||= current_user.feeds.find_by(id: params[:feed_id]) || current_user.feeds.build
  end
end
