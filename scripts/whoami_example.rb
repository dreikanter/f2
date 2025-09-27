puts 'Testing token validity...'

token_value = ENV['FREEFEED_STAGING_TOKEN']
unless token_value
  puts 'Error: FREEFEED_STAGING_TOKEN environment variable is required'
  exit 1
end

client = FreefeedClient.new(
  host: 'https://candy.freefeed.net',
  token: token_value
)

begin
  puts 'Testing whoami...'
  user = client.whoami
  puts "User: #{user[:username]} (#{user[:screen_name]}) - #{user[:email]}"

rescue => e
  puts 'Error: ' + e.message
  puts 'Class: ' + e.class.name
end
