class FeedsController < ApplicationController
  def index
    @feeds = user_feeds.order(:name)
  end

  def new
    @feed = user_feeds.build
  end

  def show
    @feed = load_feed
    @section = params[:section]

    if @section && request.format.turbo_stream?
      render turbo_stream: turbo_stream.update("edit-form-container", "")
    end
  end

  def edit
    @feed = load_feed
    @section = params[:section]

    if @section && request.format.turbo_stream?
      render turbo_stream: turbo_stream.update(
        "edit-form-container",
        partial: form_template_name(@section),
        locals: { feed: @feed }
      )
    else
      # Return blank response if no section param
      render turbo_stream: turbo_stream.update("edit-form-container", "")
    end
  end

  def create
    if using_simplified_creation?
      create_with_simplified_flow
    else
      create_with_full_attributes
    end
  end

  def update
    @feed = load_feed
    @section = params[:section]

    # Auto-disable feed if configuration becomes invalid for enabled feeds
    if @feed.enabled? && !will_be_complete_after_update?
      @feed.state = :disabled
    end

    if @feed.update(section_params)
      if @section
        streams = []
        # Update the section display
        streams << turbo_stream.update(
          "#{@section}-content",
          partial: display_template_name(@section),
          locals: { feed: @feed }
        )
        # Clear the edit form
        streams << turbo_stream.update("edit-form-container", "")
        # Update the feed title if content-source was updated
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
    @feed.destroy!
    redirect_to feeds_path, notice: "Feed was successfully deleted."
  end

  private

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

  def user_feeds
    Current.user.feeds
  end

  def load_feed
    user_feeds.find(params[:id])
  end

  def new_feed_params
    return {} unless params[:feed]

    params.require(:feed).permit(
      :name,
      :url,
      :feed_profile_id
    )
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
    return {} unless params[:feed]
    params.require(:feed).permit(:name, :url, :feed_profile_id)
  end

  def reposting_params
    return {} unless params[:feed]
    permitted_params = params.require(:feed).permit(:access_token_id, :target_group)

    # Clear access_token_id if there are no active tokens available
    unless Current.user.access_tokens.active.exists?
      permitted_params[:access_token_id] = nil
    end

    permitted_params
  end

  def scheduling_params
    return {} unless params[:feed]
    params.require(:feed).permit(:cron_expression, :import_after)
  end

  def will_be_complete_after_update?
    updated_feed = @feed.dup
    updated_feed.assign_attributes(section_params)
    updated_feed.can_be_enabled?
  end

  def using_simplified_creation?
    return false unless params[:feed]

    # If only basic fields are provided, use simplified flow
    provided_params = params[:feed].keys.map(&:to_s)
    basic_fields = %w[name url feed_profile_id]
    full_fields = %w[cron_expression access_token_id target_group state description import_after]

    # Use simplified flow if no advanced fields are provided
    (provided_params & full_fields).empty?
  end

  def create_with_simplified_flow
    @feed = user_feeds.build(new_feed_params)
    @feed.state = :disabled
    @feed.generate_unique_name!

    if @feed.save
      redirect_to @feed, notice: "Feed was successfully created. Complete the configuration to enable it."
    else
      render :new, status: :unprocessable_content
    end
  end

  def create_with_full_attributes
    @feed = user_feeds.build(feed_params)

    # Set default state to disabled for full attribute creation (backward compatibility)
    @feed.state = :disabled if @feed.state.blank?

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

  def feed_params
    return {} unless params[:feed]

    params.require(:feed).permit(
      :name,
      :url,
      :cron_expression,
      :feed_profile_id,
      :import_after,
      :description,
      :access_token_id,
      :target_group,
      :state
    )
  end
end
