class FeedsController < ApplicationController
  include Pagination

  def index
    authorize Feed
    @feeds = paginate_scope
  end

  def new
    @feed = Feed.new
    authorize @feed
  end

  def show
    @feed = load_feed
    authorize @feed
    @section = params[:section]
    @recent_posts = @feed.posts.includes(:feed_entry).order(published_at: :desc).limit(10)

    if @section && request.format.turbo_stream?
      render turbo_stream: turbo_stream.update("edit-form-container", "")
    end
  end

  def edit
    @feed = load_feed
    authorize @feed
    @section = params[:section]

    if @section && request.format.turbo_stream?
      render turbo_stream: turbo_stream.update(
        "edit-form-container",
        partial: form_template_name(@section),
        locals: { feed: @feed }
      )
    else
      render turbo_stream: turbo_stream.update("edit-form-container", "")
    end
  end

  def create
    @feed = Feed.new(feed_params)
    @feed.user = Current.user
    authorize @feed

    if @feed.save
      notice_message = "Feed was successfully created."
      if @feed.access_token&.active?
        notice_message += " You can now enable it to start processing items."
      end
      redirect_to @feed, notice: notice_message
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    @feed = load_feed
    authorize @feed
    @section = params[:section]

    if @feed.enabled? && !will_be_complete_after_update?
      @feed.state = :disabled
    end

    if @feed.update(section_params)
      if @section
        streams = []
        streams << turbo_stream.update(
          "#{@section}-content",
          partial: display_template_name(@section),
          locals: { feed: @feed }
        )
        streams << turbo_stream.update("edit-form-container", "")
        if @section == "content-source"
          streams << turbo_stream.update("feed-title", @feed.name)
        end
        render turbo_stream: streams
      else
        redirect_to @feed, notice: "Feed was successfully updated."
      end
    else
      if @section
        render turbo_stream: turbo_stream.update(
          "edit-form-container",
          partial: form_template_name(@section),
          locals: { feed: @feed }
        )
      else
        render :show, status: :unprocessable_content
      end
    end
  end

  def destroy
    @feed = load_feed
    authorize @feed
    @feed.destroy!
    redirect_to feeds_path, notice: "Feed was successfully deleted."
  end

  private

  def pagination_scope
    policy_scope(Feed).order(:name)
  end

  def form_template_name(section)
    case section
    when "content-source"
      "content_source_form"
    else
      "#{section}_form"
    end
  end

  def display_template_name(section)
    case section
    when "content-source"
      "content_source_display"
    else
      "#{section}_display"
    end
  end

  def load_feed
    policy_scope(Feed).find(params[:id])
  end

  def section_params
    return feed_params unless @section

    case @section
    when "content-source"
      content_source_params
    when "reposting"
      reposting_params
    when "scheduling"
      scheduling_params
    else
      feed_params
    end
  end

  def content_source_params
    params[:feed].permit(:name, :url, :feed_profile_id)
  end

  def reposting_params
    permitted_params = params[:feed].permit(:access_token_id, :target_group)

    unless Current.user.access_tokens.active.exists?
      permitted_params[:access_token_id] = nil
    end

    permitted_params
  end

  def scheduling_params
    params[:feed].permit(:cron_expression, :import_after)
  end

  def will_be_complete_after_update?
    updated_feed = @feed.dup
    updated_feed.assign_attributes(section_params)
    updated_feed.can_be_enabled?
  end

  def feed_params
    params.require(:feed).permit(
      :name,
      :url,
      :cron_expression,
      :feed_profile_id,
      :import_after,
      :description,
      :access_token_id,
      :target_group
    )
  end
end
