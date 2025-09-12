# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Create a test user for development
if Rails.env.development?
  user = User.find_or_create_by!(email_address: "test@example.com") do |user|
    user.password = "password"
    user.password_confirmation = "password"
  end
  puts "✅ Development user created: test@example.com / password"

  # Add admin permission to the first user
  user.permissions.find_or_create_by!(name: "admin")
  puts "✅ Admin permission granted to first user"

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
