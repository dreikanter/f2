class FeedIdentificationDescriptionComponent < EventDescriptionComponent
  def call
    helpers.safe_join([
      helpers.tag.span("Feed identification: #{result}", class: "font-medium"),
      event.metadata["input"],
      event.metadata.dig("diagnostics", "error", "message")
    ].compact, " · ")
  end

  private

  def result
    case event.metadata["status"]
    when "processing" then "checking"
    when "working" then selected_result
    when "no_feed" then "no readable feed"
    when "unreachable" then "could not reach source"
    when "timed_out" then "timed out"
    when "cancelled" then "cancelled"
    when "superseded" then "superseded by another attempt"
    else "unknown result"
    end
  end

  def selected_result
    candidate = Array(event.metadata["candidates"]).find { |item| item["test_status"] == "passed" }
    return "feed identified" unless candidate

    "#{FeedProfile.display_name_for(candidate['profile_key'])} identified (#{candidate['posts_found'].to_i} sampled posts)"
  end
end
