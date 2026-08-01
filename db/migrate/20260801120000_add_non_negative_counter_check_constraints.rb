class AddNonNegativeCounterCheckConstraints < ActiveRecord::Migration[8.0]
  CONSTRAINTS = {
    users: %w[available_invites],
    post_publications: %w[attachments_processed_count comments_published_count],
    feed_metrics: %w[posts_count invalid_posts_count published_posts_count]
  }.freeze

  def change
    CONSTRAINTS.each do |table, columns|
      columns.each do |column|
        add_check_constraint table, "#{column} >= 0", name: "#{table}_#{column}_non_negative"
      end
    end
  end
end
