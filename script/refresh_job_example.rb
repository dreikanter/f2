puts 'Testing FeedRefreshJob with staging data...'

token_value = ENV['FREEFEED_STAGING_TOKEN']

unless token_value
  puts 'Error: FREEFEED_STAGING_TOKEN environment variable is required'
  exit 1
end

# Find or create user
user = User.first || FactoryBot.create(:user)

# Find or create access token
access_token = AccessToken.find_by(name: 'test_refresh_token') || AccessToken.build_with_token(
  user: user,
  name: 'test_refresh_token',
  token: token_value,
  host: 'https://candy.freefeed.net',
  status: :active
)

unless access_token.persisted?
  access_token.save!
end

# Find or create XKCD feed profile
feed_profile = FeedProfile.find_by(name: 'test_xkcd') || FeedProfile.create!(
  user: user,
  name: 'test_xkcd',
  loader: 'http',
  processor: 'rss',
  normalizer: 'xkcd'
)

# Clean up any existing test feeds
Feed.where(target_group: 'xkcdtest').destroy_all

# Find or create test feed
feed = Feed.find_by(name: 'test_refresh_feed') || Feed.create!(
  user: user,
  access_token: access_token,
  feed_profile: feed_profile,
  name: 'test_refresh_feed',
  url: 'https://xkcd.com/rss.xml',
  target_group: 'xkcdtest',
  state: :enabled,
  cron_expression: '0 */6 * * *'
)

puts
puts '---> Using test feed:'
puts '  User: ' + user.email_address
puts '  Feed: ' + feed.name
puts '  URL: ' + feed.url
puts '  Target Group: ' + feed.target_group
puts '  State: ' + feed.state
puts '  Feed Profile: ' + feed_profile.name
puts '  Access Token: ' + access_token.name

begin
  puts
  puts '---> Starting feed refresh job...'

  start_time = Time.current
  FeedRefreshJob.perform_now(feed.id)
  duration = Time.current - start_time

  feed.reload
  posts = feed.posts.order(:published_at)

  puts
  puts '---> SUCCESS! Feed refresh completed:'
  puts '  Duration: ' + duration.round(2).to_s + ' seconds'
  puts '  Total Posts: ' + posts.count.to_s
  puts '  Published Posts: ' + posts.published.count.to_s
  puts '  Failed Posts: ' + posts.failed.count.to_s
  puts '  Rejected Posts: ' + posts.rejected.count.to_s

  if posts.published.any?
    puts
    puts '---> Published posts:'

    posts.published.each_with_index do |post, i|
      puts "  #{i + 1}. #{post.content[0..80]}#{'...' if post.content.length > 80}"
      puts "     URL: #{access_token.host}/posts/#{post.freefeed_post_id}"
      puts
    end
  end

  if posts.failed.any?
    puts
    puts '---> Failed posts:'
    posts.failed.each do |post|
      puts "  - #{post.content[0..50]}#{'...' if post.content.length > 50}"
    end
  end

  if posts.rejected.any?
    puts
    puts '---> Rejected posts:'
    posts.rejected.each do |post|
      puts "  - #{post.content[0..50]}#{'...' if post.content.length > 50} (#{post.validation_errors.join(', ')})"
    end
  end

  latest_event = feed.events.where(type: ["feed_refresh_stats", "feed_refresh_error"]).order(:created_at).last

  if latest_event
    puts
    puts '---> Workflow stats:'
    ap latest_event.metadata.fetch('stats')
  end
rescue => e
  puts
  puts 'Error: ' + e.message
  puts 'Class: ' + e.class.name
  puts 'Backtrace:'
  puts e.backtrace[0..5].join("\n")
ensure
  # Clean up test records
  puts
  puts '---> Cleaning up test records...'

  # Delete test feed and its associated records
  if defined?(feed) && feed&.persisted?
    feed.destroy!
    puts '  ✓ Deleted test feed'
  end

  # Delete test access token
  test_token = AccessToken.find_by(name: 'test_refresh_token')
  if test_token
    test_token.destroy!
    puts '  ✓ Deleted test access token'
  end

  # Delete test feed profile
  test_profile = FeedProfile.find_by(name: 'test_xkcd')
  if test_profile
    test_profile.destroy!
    puts '  ✓ Deleted test feed profile'
  end

  puts 'Cleanup complete!'
end
