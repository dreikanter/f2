class AddRepostedAtIndexToPosts < ActiveRecord::Migration[8.2]
  # Sorting the Posts page by repost date defaults to reposted_at across all of
  # the user's feeds. The existing [feed_id, reposted_at] index only helps when
  # a single feed is selected; this standalone index backs the unfiltered view.
  # Match the default ordering (DESC, reposted posts first, NULLs last) so the
  # planner can satisfy it straight from the index.
  def change
    add_index :posts, :reposted_at,
      order: { reposted_at: "DESC NULLS LAST" },
      name: "index_posts_on_reposted_at"
  end
end
