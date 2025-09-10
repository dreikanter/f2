# FreeFeed API Client
#
# Minimal client for FreeFeed API focused on specific application needs.
# Provides high-level methods for token validation and group management.
class FreefeedClient
  class Error < StandardError; end
  class UnauthorizedError < Error; end
  class NotFoundError < Error; end

  DEFAULT_OPTIONS = {
    timeout: 30,
    follow_redirects: true,
    max_redirects: 5
  }.freeze

  attr_reader :host, :http_client

  def initialize(host:, token:, http_client: nil, options: {})
    @host = host.chomp("/")
    @token = token
    @http_client = http_client || HttpClient::FaradayAdapter.new(DEFAULT_OPTIONS.merge(options))
  end

  # Validate token and get current user info
  # Used for access token validation
  def whoami
    response = get("/v4/users/whoami")
    parse_whoami_response(response.body)
  rescue HttpClient::Error => e
    raise Error, "Failed to validate token: #{e.message}"
  end

  # Get list of groups that current user can post to
  # Returns simplified array of group objects
  def managed_groups
    response = get("/v4/managedGroups")
    parse_managed_groups_response(response.body)
  rescue HttpClient::Error => e
    raise Error, "Failed to fetch managed groups: #{e.message}"
  end

  private

  def get(path, options: {})
    url = "#{@host}#{path}"
    headers = {
      "Authorization" => "Bearer #{@token}",
      "Accept" => "application/json",
      "User-Agent" => "FreeFeed-Rails-Client"
    }

    response = @http_client.get(url, headers: headers, options: options)

    case response.status
    when 200
      response
    when 401, 403
      raise UnauthorizedError, "Invalid or expired token"
    when 404
      raise NotFoundError, "Resource not found"
    else
      raise Error, "HTTP #{response.status}: #{response.body}"
    end
  end

  def parse_whoami_response(body)
    data = JSON.parse(body)
    user = data.dig("users")

    unless user && user["username"]
      raise Error, "Invalid whoami response format"
    end

    {
      id: user["id"],
      username: user["username"],
      screen_name: user["screenName"],
      email: user["email"]
    }
  rescue JSON::ParserError => e
    raise Error, "Invalid JSON response: #{e.message}"
  end

  def parse_managed_groups_response(body)
    groups = JSON.parse(body)

    unless groups.is_a?(Array)
      raise Error, "Invalid managed groups response format"
    end

    groups.map do |group|
      {
        id: group["id"],
        username: group["username"],
        screen_name: group["screenName"],
        is_private: group["isPrivate"] == "1",
        is_restricted: group["isRestricted"] == "1"
      }
    end
  rescue JSON::ParserError => e
    raise Error, "Invalid JSON response: #{e.message}"
  end
end
