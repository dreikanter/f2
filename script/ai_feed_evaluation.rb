class AiFeedEvaluation
  def self.run(credential:, model:, prompt:)
    raise ArgumentError, "Development or test only" unless Rails.env.development? || Rails.env.test?

    report = nil
    Feed.transaction(requires_new: true) do
      feed = Feed.create!(
        name: "Evaluation #{SecureRandom.hex(6)}",
        user: credential.user,
        ai_credential: credential,
        ai_model: model,
        feed_profile_key: "llm",
        state: :disabled,
        params: { "prompt" => prompt, "max_items" => 1 }
      )
      workflow = FeedRefreshWorkflow.new(feed)
      raw = feed.loader_instance.load
      # Reuse refresh selection without entering its persistence/publication steps.
      entries = workflow.send(:process_feed_contents, raw)
      selected = workflow.send(:filter_new_entries, entries)
      posts = selected.map { |entry| feed.normalizer_instance(entry).normalize }
      report = {
        usable_new_posts: posts.count(&:enqueued?),
        posts: posts.map { |post| post.attributes.slice("uid", "content", "source_url", "published_at", "status", "validation_errors") }
      }
      raise ActiveRecord::Rollback
    end
    report
  end
end
