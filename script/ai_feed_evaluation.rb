class AiFeedEvaluation
  def self.run(credential:, model:, prompt:, max_items: 1, imported_urls: [], import_after: nil)
    raise ArgumentError, "Development or test only" unless Rails.env.development? || Rails.env.test?

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    report = {
      revision: IO.popen(["git", "-C", Rails.root.to_s, "rev-parse", "HEAD"], &:read).strip,
      provider: credential.provider,
      model: model,
      started_at: Time.current.iso8601,
      time_zone: Time.zone.name,
      tool_cost_usd: "Unknown: current usage records do not separate tool charges"
    }
    Feed.transaction(requires_new: true) do
      feed = Feed.create!(
        name: "Evaluation #{SecureRandom.hex(6)}",
        user: credential.user,
        ai_credential: credential,
        ai_model: model,
        feed_profile_key: "llm",
        state: :disabled,
        import_after: import_after,
        params: { "prompt" => prompt, "max_items" => max_items }
      )
      imported_urls.each do |url|
        FeedEntryUid.create!(feed: feed, uid: Uid::Resolver.from_url(url), imported_at: Time.current)
      end
      entries = selected = posts = []
      begin
        raw = feed.loader_instance.load
        entries = feed.processor_instance(raw).process.entries.select { |entry| entry.uid.present? }
        selection = FeedEntrySelection.new(feed)
        selected = selection.call(entries)
        posts = selected.map { |entry| selection.posts.fetch(entry.uid) }
      rescue StandardError => error
        Rails.error.report(error, context: { evaluation: true })
        report[:error] = error.class.name
      end
      report.merge!(
        configuration: feed.params,
        imported_urls: imported_urls,
        import_after: import_after&.iso8601,
        candidates: entries.map(&:raw_data),
        discovered: report[:error] ? nil : entries.size,
        filtered: report[:error] ? nil : selection.stats.values_at(:collapsed_duplicate_uids, :known_entries, :entries_before_threshold).sum,
        rejected: report[:error] ? nil : selection.stats[:rejected_posts],
        usable_new_posts: posts.count(&:enqueued?),
        posts: posts.map { |post| post.attributes.slice("uid", "content", "source_url", "published_at", "status", "validation_errors") }
      )
      usages = LlmUsageReport.for_feed(feed)
      report[:usage] = usages.usages.map { |usage| usage.attributes.slice("provider", "model", "status", "input_tokens", "output_tokens", "total_cost") }
      report[:cost_totals] = usages.totals.to_h
      report[:search_calls] = usages.usages.sum { |usage| LlmUsageDetails.new(usage).web_search_count.to_i }
      report[:system_prompt] = feed.llm_chats.first&.messages&.find_by(role: "system")&.content
      report[:usage_availability] = "Retained attempts only; in-flight spend may be missing after a failure"
      report[:latency_seconds] = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      raise ActiveRecord::Rollback
    end
    report
  end
end
