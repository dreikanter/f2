# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Create a test user for development
if Rails.env.development?
  user = User.find_or_create_by!(email_address: "test@example.com") do |user|
    user.password = "password"
    user.password_confirmation = "password"
  end

  # Update existing users to have password_updated_at
  User.where(password_updated_at: nil).update_all(password_updated_at: Time.current)
  puts "✅ Development user created: test@example.com / password"

  # Add admin permission to the first user
  user.permissions.find_or_create_by!(name: "admin")
  puts "✅ Admin permission granted to first user"

  # Create RSS feed profile
  rss_profile = FeedProfile.find_or_initialize_by(name: "rss")
  rss_profile.assign_attributes(
    loader: "http",
    processor: "rss",
    normalizer: "rss",
    user: user
  )
  rss_profile.save!
  puts "✅ RSS feed profile created"

  # Create fake access tokens
  if AccessToken.count == 0
    # Create tokens individually to use enum values properly
    3.times do |i|
      AccessToken.create!(
        name: "Active Token #{i + 1}",
        owner: "testuser#{i + 1}",
        status: :active,
        user: user,
        host: "https://freefeed.net",
        encrypted_token: "fake_encrypted_token_#{i + 1}_#{SecureRandom.hex(16)}",
        last_used_at: rand(1..30).days.ago
      )
    end

    2.times do |i|
      AccessToken.create!(
        name: "Inactive Token #{i + 4}",
        owner: "testuser#{i + 4}",
        status: :inactive,
        user: user,
        host: "https://freefeed.net",
        encrypted_token: "fake_encrypted_token_#{i + 4}_#{SecureRandom.hex(16)}",
        last_used_at: rand(30..90).days.ago
      )
    end

    puts "✅ Access tokens created (#{AccessToken.count} total)"
  end

  # Create sample feeds
  active_token = AccessToken.active.first

  # Remove all existing feeds to start fresh
  Feed.destroy_all

  feeds_data = [
      {
        name: "Google Open Source Blog",
        url: "https://feeds.feedburner.com/GoogleOpenSourceBlog",
        description: "Google's official open source blog",
        target_group: "open-source",
        state: :enabled,
        cron_expression: "0 */6 * * *"
      },
      {
        name: "AWS Open Source Blog",
        url: "https://aws.amazon.com/blogs/opensource/feed/",
        description: "Amazon Web Services official blog",
        target_group: "aws-opensource",
        state: :enabled,
        cron_expression: "0 8 * * *"
      },
      {
        name: "Cloud Native Computing Foundation",
        url: "https://cncf.io/feed",
        description: "CNCF, part of the Linux Foundation",
        target_group: "cncf",
        state: :enabled,
        cron_expression: "0 12 * * *"
      },
      {
        name: "NIST News Feed",
        url: "https://www.nist.gov/news-events/news/rss.xml",
        description: "U.S. National Institute of Standards and Technology",
        target_group: "nist-news",
        state: :disabled,
        cron_expression: "0 9 * * *"
      },
      {
        name: "arXiv Computer Science",
        url: "http://rss.arxiv.org/rss/cs",
        description: "Cornell University's arXiv preprint server for computer science papers",
        target_group: "arxiv-cs",
        state: :enabled,
        cron_expression: "0 6 * * *"
      }
    ]

    feeds_data.each do |feed_data|
      feed = Feed.find_or_initialize_by(name: feed_data[:name], user: user)
      feed.assign_attributes(
        url: feed_data[:url],
        description: feed_data[:description],
        target_group: feed_data[:target_group],
        state: feed_data[:state],
        cron_expression: feed_data[:cron_expression],
        feed_profile: rss_profile,
        access_token: active_token
      )
      feed.save!

      # Create or update feed schedule
      schedule = feed.feed_schedule || feed.build_feed_schedule
      next_run = feed.state == "enabled" ? rand(1..6).hours.from_now : nil
      schedule.update!(
        next_run_at: next_run,
        last_run_at: rand(1..24).hours.ago
      )
    end
    puts "✅ Sample feeds created (#{Feed.count} total)"

  # Generate posts for active feeds using batch inserts
  if Post.count == 0
    all_feed_entries = []
    all_posts = []

    Feed.enabled.includes(:feed_profile).find_each do |feed|
      posts_count = rand(1..10)

      # Generate feed entries first
      feed_entries = []
      posts_count.times do |i|
        feed_entries << {
          feed_id: feed.id,
          uid: "#{feed.name.downcase.gsub(' ', '-')}-post-#{i + 1}-#{SecureRandom.hex(4)}",
          published_at: rand(1..30).days.ago,
          status: 1, # processed
          created_at: Time.current,
          updated_at: Time.current,
          raw_data: {
            title: "Sample Post #{i + 1} from #{feed.name}",
            content: "This is sample content for post #{i + 1} from #{feed.name}. Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.",
            link: "https://example.com/#{feed.name.downcase.gsub(' ', '-')}/post-#{i + 1}",
            published_at: rand(1..30).days.ago.iso8601
          }
        }
      end

      all_feed_entries.concat(feed_entries)
    end

    # Batch insert feed entries
    FeedEntry.insert_all!(all_feed_entries) if all_feed_entries.any?
    puts "✅ Feed entries created (#{FeedEntry.count} total)"

    # Generate posts for each feed entry
    FeedEntry.includes(:feed).find_each do |entry|
      post_data = entry.raw_data
      all_posts << {
        feed_id: entry.feed_id,
        feed_entry_id: entry.id,
        uid: entry.uid,
        content: post_data["content"] || "Sample content",
        source_url: post_data["link"] || "https://example.com/post",
        published_at: entry.published_at,
        status: 1, # published
        freefeed_post_id: "ff_#{SecureRandom.hex(8)}",
        attachment_urls: [],
        comments: [],
        validation_errors: [],
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    # Batch insert posts
    Post.insert_all!(all_posts) if all_posts.any?
    puts "✅ Posts created using batch inserts (#{Post.count} total)"
  end

  # Create sample events for development
  if Event.count < 75
    # Feed processing events
    Event.create!(
      type: "FeedRefresh",
      level: "info",
      message: "Feed refreshed successfully",
      user: user,
      metadata: {
        url: "https://example.com/feed.xml",
        posts_count: 12,
        duration_ms: 1234
      }
    )

    Event.create!(
      type: "FeedError",
      level: "error",
      message: "Failed to fetch feed: Connection timeout",
      user: user,
      metadata: {
        url: "https://broken-feed.example.com/feed.xml",
        error_code: "TIMEOUT",
        retry_count: 3
      }
    )

    # User events
    Event.create!(
      type: "UserLogin",
      level: "info",
      message: "User logged in successfully",
      user: user,
      metadata: {
        ip_address: "192.168.1.100",
        user_agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
      }
    )

    Event.create!(
      type: "PasswordReset",
      level: "warning",
      message: "Password reset requested",
      user: user,
      metadata: {
        ip_address: "203.0.113.195",
        timestamp: Time.current.rfc3339
      }
    )

    # System events
    Event.create!(
      type: "SystemMaintenance",
      level: "info",
      message: "Scheduled maintenance completed",
      user: nil,
      metadata: {
        maintenance_type: "database_cleanup",
        records_purged: 1500,
        duration_minutes: 15
      }
    )

    Event.create!(
      type: "BackgroundJobError",
      level: "error",
      message: "Background job failed with timeout",
      user: nil,
      metadata: {
        job_class: "FeedRefreshJob",
        job_id: "abc123",
        queue: "default",
        attempts: 3,
        error: "execution expired"
      }
    )

    # Debug events
    Event.create!(
      type: "ApiRequest",
      level: "debug",
      message: "External API request completed",
      user: user,
      metadata: {
        endpoint: "/api/v1/feeds/validate",
        method: "POST",
        response_time_ms: 245,
        status_code: 200
      }
    )

    Event.create!(
      type: "CacheHit",
      level: "debug",
      message: "Cache hit for feed data",
      user: nil,
      metadata: {
        cache_key: "feed:123:content",
        ttl_remaining: 1800
      }
    )

    # Events with expiration
    Event.create!(
      type: "TempDebugFlag",
      level: "warning",
      message: "Debug flag enabled temporarily",
      user: user,
      expires_at: 1.hour.from_now,
      metadata: {
        flag_name: "verbose_logging",
        enabled_by: user.email_address
      }
    )

    Event.create!(
      type: "SecurityAlert",
      level: "error",
      message: "Multiple failed login attempts detected",
      user: nil,
      expires_at: 24.hours.from_now,
      metadata: {
        ip_address: "198.51.100.42",
        attempts_count: 8,
        time_window_minutes: 10
      }
    )

    # Generate additional events to reach 75 total for pagination testing
    current_count = Event.count
    events_needed = 75 - current_count

    event_types = [
      "FeedRefresh",
      "FeedError",
      "UserLogin",
      "PasswordReset",
      "SystemMaintenance",
      "BackgroundJobError",
      "ApiRequest",
      "CacheHit",
      "SecurityAlert",
      "DatabaseQuery"
    ]

    levels = [
      "debug",
      "info",
      "warning",
      "error"
    ]

    events_needed.times do |i|
      Event.create!(
        type: event_types.sample,
        level: levels.sample,
        message: "Generated event #{i + current_count + 1} for pagination testing",
        user: (i.even? ? user : nil),
        metadata: {
          event_number: i + current_count + 1,
          batch: "pagination_test",
          generated_at: Time.current.rfc3339
        }
      )
    end

    puts "✅ Sample events created (#{Event.count} total)"
  end
end
