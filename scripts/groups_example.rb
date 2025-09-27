puts 'Testing managed groups access...'

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
  puts 'Fetching managed groups...'
  groups = client.managed_groups

  puts "Found #{groups.length} managed groups:"
  groups.each do |group|
    puts "  - #{group[:username]} (#{group[:screen_name]}) - Private: #{group[:is_private]}, Restricted: #{group[:is_restricted]}"
  end

  private_groups = groups.select { |g| g[:is_private] }
  puts "\nPrivate groups for testing:"
  private_groups.each do |group|
    puts "  - #{group[:username]} (suitable for testing)"
  end

rescue => e
  puts 'Error: ' + e.message
  puts 'Class: ' + e.class.name
  puts 'Backtrace:'
  puts e.backtrace[0..3].join("\n")
end
