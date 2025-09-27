puts 'Testing FeedRefreshJob with staging data...'

token_value = ENV['FREEFEED_STAGING_TOKEN']
unless token_value
  puts 'Error: FREEFEED_STAGING_TOKEN environment variable is required'
  exit 1
end

user = User.first || FactoryBot.create(:user)

access_token = AccessToken.build_with_token(
  user: user,
  name: 'Feed Refresh Test Token ' + Time.now.to_i.to_s,
  token: token_value,
  host: 'https://candy.freefeed.net',
  status: :active
)

access_token.save!
feed_profile = FeedProfile.first || FactoryBot.create(:feed_profile)

feed = Feed.create!(
  user: user,
  access_token: access_token,
  feed_profile: feed_profile,
  name: 'Refresh Test Feed ' + Time.now.to_i.to_s,
  url: 'https://xkcd.com/rss.xml',
  target_group: 'xkcdtest',
  state: :enabled,
  cron_expression: '0 */6 * * *'
)

puts 'Created test feed:'
puts '  User: ' + user.email_address
puts '  Feed: ' + feed.name
puts '  URL: ' + feed.url
puts '  Target Group: ' + feed.target_group
puts '  State: ' + feed.state

begin
  puts 'Starting feed refresh job...'

  start_time = Time.current
  FeedRefreshJob.perform_now(feed.id)
  duration = Time.current - start_time

  feed.reload
  posts = feed.posts.order(:published_at)

  puts 'SUCCESS! Feed refresh completed:'
  puts '  Duration: ' + duration.round(2).to_s + ' seconds'
  puts '  Total Posts: ' + posts.count.to_s
  puts '  Published Posts: ' + posts.published.count.to_s
  puts '  Failed Posts: ' + posts.failed.count.to_s
  puts '  Rejected Posts: ' + posts.rejected.count.to_s

  if posts.published.any?
    puts 'Sample published posts:'
    posts.published.limit(3).each_with_index do |post, i|
      puts "  #{i + 1}. #{post.content[0..80]}#{'...' if post.content.length > 80}"
      puts "     FreeFeed ID: #{post.freefeed_post_id}"
      puts "     URL: #{access_token.host}/posts/#{post.freefeed_post_id}"
    end
  end

  if posts.failed.any?
    puts 'Failed posts:'
    posts.failed.each do |post|
      puts "  - #{post.content[0..50]}#{'...' if post.content.length > 50}"
    end
  end

  if posts.rejected.any?
    puts 'Rejected posts:'
    posts.rejected.each do |post|
      puts "  - #{post.content[0..50]}#{'...' if post.content.length > 50} (#{post.validation_errors.join(', ')})"
    end
  end

  latest_event = feed.feed_refresh_events.order(:created_at).last
  if latest_event
    puts 'Workflow stats:'
    stats = latest_event.stats || {}
    puts "  Total duration: #{stats['total_duration']&.round(2)} seconds" if stats['total_duration']
    puts "  Content size: #{stats['content_size']} bytes" if stats['content_size']
    puts "  Total entries: #{stats['total_entries']}" if stats['total_entries']
    puts "  New entries: #{stats['new_entries']}" if stats['new_entries']
    puts "  New posts: #{stats['new_posts']}" if stats['new_posts']
    puts "  Published posts: #{stats['published_posts']}" if stats['published_posts']
    puts "  Failed posts: #{stats['failed_posts']}" if stats['failed_posts']
    puts "  Rejected posts: #{stats['rejected_posts']}" if stats['rejected_posts']
  end

rescue => e
  puts 'Error: ' + e.message
  puts 'Class: ' + e.class.name
  puts 'Backtrace:'
  puts e.backtrace[0..5].join("\n")
end