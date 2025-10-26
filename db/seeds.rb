# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Create a test user for development
if Rails.env.development?
  dev_password = "password123"

  user = User.find_or_initialize_by(email_address: "test@example.com").tap do |user|
    user.password = dev_password
    user.password_confirmation = dev_password
  end

  user.save!

  # Update existing users to have password_updated_at
  User.where(password_updated_at: nil).update_all(password_updated_at: Time.current)
  puts "✅ Development user created: #{user.email_address} / #{dev_password}"

  # Add admin permission to the first user
  user.permissions.find_or_create_by!(name: "admin")
  puts "✅ Admin permission granted to first user"

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
        token: "fake_token_#{i + 1}_#{SecureRandom.hex(16)}",
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
        token: "fake_token_#{i + 4}_#{SecureRandom.hex(16)}",
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
        feed_profile_key: "rss",
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

    Feed.enabled.find_each do |feed|
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
    events = []
    base_time = Time.current

    # Email events for the user
    [
      { type: "email_sent", level: :info, message: "Email sent to #{user.email_address}", days_ago: 30 },
      { type: "email_delivered", level: :info, message: "Email delivered to #{user.email_address}", days_ago: 30 },
      { type: "email_opened", level: :info, message: "Email opened by #{user.email_address}", days_ago: 29 },
      { type: "email_clicked", level: :info, message: "Email clicked by #{user.email_address}", days_ago: 28 },
      { type: "email_changed", level: :info, message: "Email changed from old@example.com to #{user.email_address}", days_ago: 60,
        metadata: { old_email: "old@example.com", new_email: user.email_address } }
    ].each do |event_data|
      events << {
        type: event_data[:type],
        level: event_data[:level],
        subject_type: "User",
        subject_id: user.id,
        user_id: user.id,
        message: event_data[:message],
        metadata: event_data[:metadata] || {},
        created_at: base_time - event_data[:days_ago].days,
        updated_at: base_time - event_data[:days_ago].days
      }
    end

    # Feed refresh events for each feed
    Feed.limit(3).each do |feed|
      # Successful refresh
      events << {
        type: "feed_refresh",
        level: :info,
        subject_type: "Feed",
        subject_id: feed.id,
        user_id: feed.user_id,
        message: "Feed refresh completed for #{feed.name}",
        metadata: {
          stats: {
            started_at: (base_time - 2.hours).iso8601,
            completed_at: (base_time - 2.hours + 3.seconds).iso8601,
            total_duration: 3.2,
            new_entries: rand(3..10),
            new_posts: rand(1..8)
          }
        },
        created_at: base_time - 2.hours,
        updated_at: base_time - 2.hours
      }

      # Add an error event for one feed
      if feed == Feed.first
        events << {
          type: "feed_refresh_error",
          level: :error,
          subject_type: "Feed",
          subject_id: feed.id,
          user_id: feed.user_id,
          message: "Feed refresh failed at load_feed_contents: Connection timeout",
          metadata: {
            stats: { started_at: (base_time - 5.hours).iso8601 },
            error: {
              class: "Net::ReadTimeout",
              message: "execution expired",
              stage: "load_feed_contents",
              backtrace: ["lib/feed_loader.rb:42:in `load'"]
            }
          },
          created_at: base_time - 5.hours,
          updated_at: base_time - 5.hours
        }
      end
    end

    # Generate varied events to reach 75 total for pagination testing
    events_needed = 75 - Event.count - events.length

    event_templates = [
      { type: "feed_refresh", level: :info, weight: 40 },
      { type: "feed_refresh_error", level: :error, weight: 5 },
      { type: "email_sent", level: :info, weight: 15 },
      { type: "email_delivered", level: :info, weight: 15 },
      { type: "email_opened", level: :info, weight: 10 },
      { type: "email_clicked", level: :info, weight: 5 },
      { type: "email_bounced", level: :warning, weight: 3 },
      { type: "email_failed", level: :error, weight: 2 },
      { type: "email_delayed", level: :info, weight: 3 },
      { type: "email_changed", level: :info, weight: 2 }
    ]

    # Create weighted array for realistic distribution
    weighted_templates = event_templates.flat_map { |t| [t] * t[:weight] }
    feeds_array = Feed.all.to_a

    events_needed.times do |i|
      template = weighted_templates.sample
      days_ago = rand(1..30)
      time = base_time - days_ago.days - rand(0..23).hours

      case template[:type]
      when "feed_refresh"
        feed = feeds_array.sample
        next unless feed

        events << {
          type: template[:type],
          level: template[:level],
          subject_type: "Feed",
          subject_id: feed.id,
          user_id: feed.user_id,
          message: "Feed refresh completed for #{feed.name}",
          metadata: { stats: { new_entries: rand(0..5), new_posts: rand(0..3) } },
          created_at: time,
          updated_at: time
        }
      when "feed_refresh_error"
        feed = feeds_array.sample
        next unless feed

        events << {
          type: template[:type],
          level: template[:level],
          subject_type: "Feed",
          subject_id: feed.id,
          user_id: feed.user_id,
          message: "Feed refresh failed at #{['load_feed_contents', 'process_feed_contents', 'publish_posts'].sample}: #{['Connection timeout', 'Invalid XML', 'Rate limit exceeded'].sample}",
          metadata: { error: { class: "StandardError", message: "Error occurred" } },
          created_at: time,
          updated_at: time
        }
      else
        events << {
          type: template[:type],
          level: template[:level],
          subject_type: "User",
          subject_id: user.id,
          user_id: user.id,
          message: "Sample #{template[:type]} event",
          metadata: {},
          created_at: time,
          updated_at: time
        }
      end
    end

    # Batch insert all events
    Event.insert_all!(events) if events.any?
    puts "✅ Sample events created using batch insert (#{Event.count} total)"
  end
end
