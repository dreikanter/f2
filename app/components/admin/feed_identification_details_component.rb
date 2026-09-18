module Admin
  class FeedIdentificationDetailsComponent < ViewComponent::Base
    def initialize(event:)
      @metadata = event.metadata
    end

    def call
      render(DescriptionListComponent.new) do |list|
        list.with_item(item("Source", @metadata["input"], "source"))
        list.with_item(item("Attempt", @metadata["run_id"], "run"))
        list.with_item(item("Result", @metadata["status"].to_s.humanize, "result"))
        if diagnostics["error"]
          list.with_item(item("Error", error_text(diagnostics["error"]), "error"))
        end
        Array(diagnostics["fetches"]).each do |fetch|
          list.with_item(item("HTTP request", fetch_details(fetch), "fetch"))
        end
        Array(diagnostics["candidate_tests"]).each do |candidate|
          list.with_item(item("Candidate", candidate_details(candidate), "candidate"))
        end
      end
    end

    private

    def diagnostics
      @metadata.fetch("diagnostics", {})
    end

    def item(label, value, key)
      StatListItemComponent.new(label: label, value: value, key: "events.identification.#{key}")
    end

    def fetch_details(fetch)
      parts = [fetch["url"]]
      parts << "Redirected to #{fetch['resolved_url']}" if fetch["resolved_url"].present? && fetch["resolved_url"] != fetch["url"]
      parts << "HTTP #{fetch['http_status']}" if fetch["http_status"]
      parts << fetch["content_type"] if fetch["content_type"].present?
      parts << "#{fetch['body_bytes']} bytes" if fetch["body_bytes"]
      parts << error_text(fetch["error"]) if fetch["error"]
      lines(parts)
    end

    def candidate_details(candidate)
      lines([
        "#{candidate['profile_key']}: #{candidate['status']}",
        candidate["url"],
        "#{candidate['posts_found']} sampled posts",
        *Array(candidate["errors"]).map { |error| error_text(error) }
      ])
    end

    def error_text(error)
      [error["class"], error["message"]].compact_blank.join(": ")
    end

    def lines(parts)
      helpers.safe_join(parts.map { |part| helpers.tag.div(part) })
    end
  end
end
