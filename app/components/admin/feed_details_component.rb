class Admin::FeedDetailsComponent < ViewComponent::Base
  def initialize(feed:)
    @feed = feed
  end

  def call
    missing_setup = @feed.missing_enablement_parts

    render(DescriptionListComponent.new) do |list|
      add_item(list, :id, "Feed ID", helpers.tag.code(@feed.id))
      add_item(list, :owner, "Owner", owner_value)
      add_item(list, :status, "Status", render(helpers.feed_status_badge(@feed)))
      add_item(list, :setup, "Missing setup", missing_setup.to_sentence) if missing_setup.any?
      add_item(list, :profile, "Profile", profile_value)
      add_item(list, :source, source_label, source_value)
      add_item(list, :description, "Description", wrapped_text(@feed.description))
      add_item(list, :target_group, "Target group", helpers.feed_target_group_link(@feed) || "Not configured")
      add_item(list, :access_token, "Access token", access_token_value)
      add_item(list, :schedule, "Schedule", schedule_value)

      if @feed.scheduled?
        add_item(list, :last_scheduled_run, "Last scheduled run", optional_time(@feed.feed_schedule&.last_run_at))
        add_item(list, :next_run, "Next scheduled run", next_run_value)
        add_item(list, :failures, "Consecutive failures", "#{@feed.consecutive_failures} / #{Feed::MAX_CONSECUTIVE_FAILURES}")
        add_item(list, :import_after, "Import posts after", optional_time(@feed.import_after, fallback: "No cutoff"))
        add_item(list, :images_only, "Images only", yes_no(@feed.images_only))
      end

      add_item(list, :last_success, @feed.sourceless? ? "Last post received" : "Last successful refresh", optional_time(@feed.last_successful_refresh_at))
      add_ai_items(list) if @feed.depends_on_ai?

      FeedProfile.options_for(@feed.feed_profile_key).each do |option|
        add_item(list, "option.#{option.name}", option.title, option_value(option))
      end

      add_item(list, :created_at, "Created", optional_time(@feed.created_at))
      add_item(list, :updated_at, "Updated", optional_time(@feed.updated_at))
    end
  end

  private

  def add_item(list, key, label, value)
    list.with_item(StatListItemComponent.new(label: label, value: value, key: "feed_details.#{key}", truncate: false))
  end

  def owner_value
    return "Not configured" unless @feed.user

    helpers.link_to(@feed.user.email_address, helpers.admin_user_path(@feed.user), class: helpers.text_link_classes)
  end

  def profile_value
    return "Not configured" if @feed.feed_profile_key.blank?

    helpers.safe_join([FeedProfile.display_name_for(@feed.feed_profile_key), " (", helpers.tag.code(@feed.feed_profile_key), ")"])
  end

  def source_label
    return "Source URL" if @feed.source_input_url?

    @feed.depends_on_ai? ? "Source prompt" : "Source"
  end

  def source_value
    return "Webhook-driven" if @feed.sourceless?
    return "Not configured" if @feed.source_input.blank?

    url = SourceLink.canonical(@feed.source_input)
    return wrapped_text(@feed.source_input) unless url

    helpers.link_to(@feed.source_input, url, class: "#{helpers.text_link_classes} break-all", target: "_blank", rel: "noopener")
  end

  def wrapped_text(text)
    helpers.tag.span(text, class: "whitespace-pre-wrap break-all") if text.present?
  end

  def access_token_value
    token = @feed.access_token
    return "Not configured" unless token

    credential_with_status(token.name, token.state.humanize, token.active?)
  end

  def credential_with_status(name, status, active)
    helpers.safe_join([name, " ", render(BadgeComponent.new(text: status, color: active ? :success : :warning))])
  end

  def schedule_value
    return "Webhook-driven" if @feed.sourceless?
    return "Not configured" unless @feed.scheduled?
    return "Every #{ActiveSupport::Duration.build(@feed.refresh_interval).inspect}" if @feed.refresh_interval.present?
    return "Not configured" if @feed.cron_expression.blank?

    helpers.safe_join(["Cron: ", helpers.tag.code(@feed.cron_expression)])
  end

  def next_run_value
    return "Not scheduled (#{@feed.state})" unless @feed.enabled?

    time = @feed.feed_schedule&.next_run_at
    return "Not scheduled" unless time
    return helpers.safe_join([optional_time(time), " (due)"]) if time <= Time.current

    helpers.tag.time("#{helpers.long_time_format(time)} (in #{helpers.time_distance(time - Time.current)})", datetime: time.rfc3339)
  end

  def optional_time(time, fallback: "Never")
    time ? helpers.datetime_with_duration_tag(time) : helpers.tag.span(fallback, class: "text-muted")
  end

  def yes_no(value)
    value ? "Yes" : "No"
  end

  def add_ai_items(list)
    add_item(list, :ai_credential, "AI credential", provider_credential_value(@feed.ai_credential))
    add_item(list, :ai_model, "AI model", @feed.ai_model.present? ? helpers.tag.code(@feed.ai_model) : "Not configured")
    add_item(list, :search_credential, "Search credential", provider_credential_value(@feed.search_credential))
  end

  def provider_credential_value(credential)
    return "Not configured" unless credential

    credential_with_status("#{credential.provider_name} — #{credential.display_name}", credential.active? ? "Active" : "Inactive", credential.active?)
  end

  def option_value(option)
    stored = (@feed.params || {})[option.name]
    value = stored.nil? ? option.default : stored
    return option.name == "max_comments" ? "No limit" : "Not set" if value.nil?

    formatted = option.boolean? ? yes_no(value) : value.to_s
    stored.nil? ? "#{formatted} (default)" : formatted
  end
end
