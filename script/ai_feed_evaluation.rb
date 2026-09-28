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
      window: "Unavailable: current contract expresses dates only in the prompt",
      source_verification: "Unavailable: current loader does not verify source facts",
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
      workflow = FeedRefreshWorkflow.new(feed)
      raw = feed.loader_instance.load
      # Reuse refresh selection without entering its persistence/publication steps.
      entries = workflow.send(:process_feed_contents, raw)
      selected = workflow.send(:filter_new_entries, entries)
      posts = selected.map { |entry| feed.normalizer_instance(entry).normalize }
      report.merge!(
        configuration: feed.params,
        imported_urls: imported_urls,
        import_after: import_after&.iso8601,
        candidates: entries.map(&:raw_data),
        discovered: entries.size,
        filtered: entries.size - selected.size,
        rejected: posts.count(&:rejected?),
        usable_new_posts: posts.count(&:enqueued?),
        posts: posts.map { |post| post.attributes.slice("uid", "content", "source_url", "published_at", "status", "validation_errors") }
      )
      usages = LlmUsageReport.for_feed(feed)
      report[:usage] = usages.usages.map { |usage| usage.attributes.slice("provider", "model", "status", "input_tokens", "output_tokens", "total_cost") }
      report[:cost_totals] = usages.totals.to_h
      report[:search_calls] = usages.usages.sum { |usage| LlmUsageDetails.new(usage).web_search_count.to_i }
      report[:system_prompt] = feed.llm_chats.sole.messages.find_by!(role: "system").content
      report[:latency_seconds] = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      raise ActiveRecord::Rollback
    end
    report
  end
end
