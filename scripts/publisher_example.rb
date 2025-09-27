puts 'Testing FreefeedPublisher with real staging data...'

# First, let's create a realistic test setup
user = User.first || FactoryBot.create(:user)

token_value = ENV['FREEFEED_STAGING_TOKEN']
unless token_value
  puts 'Error: FREEFEED_STAGING_TOKEN environment variable is required'
  exit 1
end

access_token = AccessToken.build_with_token(
  user: user,
  name: 'FreeFeed Test Token ' + Time.now.to_i.to_s,
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
  name: 'Test Feed ' + Time.now.to_i.to_s,
  url: 'https://example.com/test.xml',
  target_group: 'xkcdtest',
  state: :enabled,
  cron_expression: '0 */6 * * *'
)

feed_entry = FeedEntry.create!(
  feed: feed,
  uid: 'test-entry-' + Time.now.to_i.to_s,
  published_at: Time.current,
  status: :processed
)

# Use a random photo URL from Picsum
puts 'Using random photo from Picsum...'
photo_url = "https://picsum.photos/800/600?random=#{Time.now.to_i}"
puts "Photo URL: #{photo_url}"

post = Post.create!(
  feed: feed,
  feed_entry: feed_entry,
  uid: 'test-post-' + Time.now.to_i.to_s,
  content: 'Test post with random photo created via FreefeedPublisher service - ' + Time.now.strftime('%Y-%m-%d %H:%M:%S'),
  attachment_urls: [photo_url],
  published_at: Time.current,
  source_url: 'https://example.com/test-post',
  status: :draft
)

puts 'Created test data:'
puts '  User: ' + user.email_address
puts '  Feed: ' + feed.name + ' -> ' + feed.target_group
puts '  Post: ' + post.content[0..50] + '...'

begin
  puts 'Testing FreefeedPublisher...'

  publisher = FreefeedPublisher.new(post)
  freefeed_post_id = publisher.publish

  puts 'SUCCESS! Post published:'
  puts '  FreeFeed Post ID: ' + freefeed_post_id
  puts '  Post URL: ' + access_token.host + '/posts/' + freefeed_post_id
  puts '  Local Post Status: ' + post.reload.status
  puts '  Local Post FreeFeed ID: ' + post.freefeed_post_id.to_s

rescue => e
  puts 'Error: ' + e.message
  puts 'Class: ' + e.class.name
  puts 'Backtrace:'
  puts e.backtrace[0..3].join("\n")
end
