puts 'Testing FreefeedPublisher with comments...'

# Create test data
user = User.first || FactoryBot.create(:user)

token_value = ENV['FREEFEED_STAGING_TOKEN']

unless token_value
  puts 'Error: FREEFEED_STAGING_TOKEN environment variable is required'
  exit 1
end

access_token = AccessToken.build_with_token(
  user: user,
  name: 'FreeFeed Test Token Comments ' + Time.now.to_i.to_s,
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
  name: 'Test Feed Comments ' + Time.now.to_i.to_s,
  url: 'https://example.com/test.xml',
  target_group: 'xkcdtest',
  state: :enabled,
  cron_expression: '0 */6 * * *'
)

feed_entry = FeedEntry.create!(
  feed: feed,
  uid: 'test-entry-comments-' + Time.now.to_i.to_s,
  published_at: Time.current,
  status: :processed
)

# Use a random photo URL from Picsum
puts 'Using random photo from Picsum...'
photo_url = "https://picsum.photos/600/400?random=#{Time.now.to_i}"
puts "Photo URL: #{photo_url}"

post = Post.create!(
  feed: feed,
  feed_entry: feed_entry,
  uid: 'test-post-comments-' + Time.now.to_i.to_s,
  content: 'Test post with photo and comments created via FreefeedPublisher - ' + Time.now.strftime('%Y-%m-%d %H:%M:%S'),
  attachment_urls: [photo_url],
  comments: [
    'This is the first comment from the RSS feed',
    'And this is a second comment to test multiple comments',
    'Check out this random photo from Picsum!'
  ],
  published_at: Time.current,
  source_url: 'https://example.com/test-post-comments',
  status: :draft
)

puts 'Created test data with comments:'
puts '  Post: ' + post.content[0..50] + '...'
puts '  Comments: ' + post.comments.length.to_s + ' comments'

post.comments.each_with_index do |comment, i|
  puts "    #{i + 1}. #{comment[0..50]}#{'...' if comment.length > 50}"
end

begin
  puts 'Testing FreefeedPublisher with comments...'

  publisher = FreefeedPublisher.new(post)
  freefeed_post_id = publisher.publish

  puts 'SUCCESS! Post with comments published:'
  puts '  FreeFeed Post ID: ' + freefeed_post_id
  puts '  Post URL: ' + access_token.host + '/posts/' + freefeed_post_id
  puts '  Local Post Status: ' + post.reload.status
rescue => e
  puts 'Error: ' + e.message
  puts 'Class: ' + e.class.name
  puts 'Backtrace:'
  puts e.backtrace[0..3].join("\n")
end
