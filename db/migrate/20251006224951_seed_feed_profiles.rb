class SeedFeedProfiles < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      INSERT INTO feed_profiles (name, loader, processor, normalizer, created_at, updated_at)
      VALUES
        ('rss', 'http', 'rss', 'rss', NOW(), NOW()),
        ('xkcd', 'http', 'rss', 'xkcd', NOW(), NOW())
      ON CONFLICT (name) DO NOTHING
    SQL
  end

  def down
    execute <<~SQL
      DELETE FROM feed_profiles WHERE name IN ('rss', 'xkcd')
    SQL
  end
end
