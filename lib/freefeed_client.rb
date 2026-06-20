# FreeFeed API Client
#
# Minimal client for FreeFeed API focused on specific application needs.
# Provides high-level methods for token validation and group management.
class FreefeedClient
  class Error < StandardError; end
  class UnauthorizedError < Error; end
  class InvalidTokenError < UnauthorizedError; end
  # The token is valid but isn't allowed to perform this action — e.g. it lost
  # permission to post to a target group. Deliberately not a subclass of
  # UnauthorizedError so callers don't mistake it for a dead token and disable it.
  class ForbiddenError < Error; end
  class NotFoundError < Error; end

  USER_AGENT = "FreeFeed-Rails-Client".freeze

  DEFAULT_OPTIONS = {
    timeout: 30,
    follow_redirects: true,
    max_redirects: 5
  }.freeze

  attr_reader :host, :http_client

  # Used as the cooldown when a 429 response carries no usable Retry-After.
  # FreeFeed never sends Retry-After, and its blocks escalate from 1 up to
  # 8 minutes on repeat breaches, so back off for several minutes rather than
  # retrying into a block that is still in force.
  DEFAULT_RETRY_AFTER = 300

  # Padding added to a parsed Retry-After. The header reflects the start of the
  # server's window; a little extra keeps the retry clear of clock skew and the
  # window's edge so it doesn't land back inside a still-active block.
  RETRY_AFTER_BUFFER = 10

  def initialize(host:, token:, http_client: nil, rate_limit_subject: nil, options: {})
    @host = host.chomp("/")
    @token = token
    @rate_limit_subject = rate_limit_subject
    @http_client = http_client || HttpClient.build(DEFAULT_OPTIONS.merge(options))
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

  # Create attachment
  # @param file_path [String] path to the file to upload
  # @param content_type [String, nil] optional MIME type of the file
  # @return [Hash] attachment data with id
  def create_attachment(file_path, content_type: nil)
    content_type ||= Marcel::MimeType.for(name: file_path) || "application/octet-stream"

    payload = {
      file: Faraday::Multipart::FilePart.new(file_path, content_type)
    }

    response = post("/v1/attachments", body: payload)
    parse_attachment_response(response.body)
  rescue HttpClient::Error => e
    raise Error, "Failed to upload attachment: #{e.message}"
  end

  # Create attachment from IO object
  # @param io [IO] IO object containing the file data
  # @param content_type [String, nil] optional MIME type of the file
  # @return [Hash] attachment data with id
  def create_attachment_from_io(io, content_type: nil)
    content_type ||= Marcel::MimeType.for(io) || "application/octet-stream"

    payload = {
      file: Faraday::Multipart::FilePart.new(io, content_type)
    }

    response = post("/v1/attachments", body: payload)
    parse_attachment_response(response.body)
  rescue HttpClient::Error => e
    raise Error, "Failed to upload attachment: #{e.message}"
  end

  # Create post
  # @param body [String] post content
  # @param feeds [Array<String>] array of feed usernames/ids to post to
  # @param attachment_ids [Array<String>] array of attachment IDs
  # @return [Hash] post data with id
  def create_post(body:, feeds: [], attachment_ids: [])
    payload = {
      post: {
        body: body
      },
      meta: {
        feeds: feeds
      }
    }

    payload[:post][:attachments] = attachment_ids if attachment_ids.any?

    response = post("/v4/posts",
                   body: payload.to_json,
                   headers: { "Content-Type" => "application/json" })

    parse_post_response(response.body)
  rescue HttpClient::Error => e
    raise Error, "Failed to create post: #{e.message}"
  end

  # Create comment
  # @param post_id [String] ID of the post to comment on
  # @param body [String] comment content
  # @return [Hash] comment data with id
  def create_comment(post_id:, body:)
    payload = {
      comment: {
        body: body,
        postId: post_id
      }
    }

    response = post("/v4/comments",
                   body: payload.to_json,
                   headers: { "Content-Type" => "application/json" })

    parse_comment_response(response.body)
  rescue HttpClient::Error => e
    raise Error, "Failed to create comment: #{e.message}"
  end

  # Delete post
  # @param post_id [String] ID of the post to delete
  # @return [Boolean] true if deletion was successful
  def delete_post(post_id)
    delete("/v4/posts/#{post_id}")
    true
  rescue HttpClient::Error => e
    raise Error, "Failed to delete post: #{e.message}"
  end

  private

  def get(path, options: {})
    url = "#{@host}#{path}"
    response = @http_client.get(url, headers: auth_headers, options: options)
    handle_response(response)
  end

  def post(path, body: nil, headers: {})
    url = "#{@host}#{path}"
    response = @http_client.post(url, body: body, headers: headers.merge(auth_headers))
    handle_response(response)
  end

  def delete(path)
    url = "#{@host}#{path}"
    response = @http_client.delete(url, headers: auth_headers)
    handle_response(response)
  end

  def auth_headers
    {
      "Authorization" => "Bearer #{@token}",
      "Accept" => "application/json",
      "User-Agent" => USER_AGENT
    }
  end

  def handle_response(response)
    case response.status
    when 200, 201
      response
    when 401, 403
      err = (JSON.parse(response.body)["err"] rescue nil)
      case err
      when "inactive or expired token"
        raise InvalidTokenError, err
      when /\AYou can not post to/
        # FreeFeed rejects the destination, not the token (group went private or
        # restricted, or the user was removed from it). See PostsController#create
        # (getDestinationFeeds) in freefeed-server.
        raise ForbiddenError, err
      else
        raise UnauthorizedError, err || "Unauthorized"
      end
    when 404
      # Preserve the server's message ("Account '<name>' was not found") so the
      # caller can explain a vanished/renamed target group.
      err = (JSON.parse(response.body)["err"] rescue nil)
      raise NotFoundError, err || "Resource not found"
    when 429
      handle_too_many_requests(response)
    else
      raise Error, "HTTP #{response.status}: #{response.body}"
    end
  end

  # FreeFeed throttled us. Record the cooldown so later acquires short-circuit,
  # then raise Throttled so the job reschedules (handled by RateLimited).
  def handle_too_many_requests(response)
    retry_after = retry_after_seconds(response)
    RateLimit.penalize(:freefeed, subject: @rate_limit_subject, retry_after: retry_after) if @rate_limit_subject
    raise RateLimit::Throttled.new(retry_after: retry_after)
  end

  def retry_after_seconds(response)
    seconds = response.headers["retry-after"].to_i
    seconds.positive? ? seconds + RETRY_AFTER_BUFFER : DEFAULT_RETRY_AFTER
  end

  # TBD: Consider simplifying response processing. Probably keep the keys
  #   as is, just coerce some of the values when it makes sense. Also consider
  #   unifying draft implementation of the response processing methods
  #   since they are basically identical.

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

  def parse_attachment_response(body)
    data = JSON.parse(body)
    attachment = data.dig("attachments")

    unless attachment && attachment["id"]
      raise Error, "Invalid attachment response format"
    end

    {
      id: attachment["id"],
      url: attachment["url"],
      thumbnail_url: attachment["thumbnailUrl"],
      filename: attachment["fileName"],
      file_size: attachment["fileSize"],
      media_type: attachment["mediaType"]
    }
  rescue JSON::ParserError => e
    raise Error, "Invalid JSON response: #{e.message}"
  end

  def parse_post_response(body)
    data = JSON.parse(body)
    post = data.dig("posts")

    unless post && post["id"]
      raise Error, "Invalid post response format"
    end

    {
      id: post["id"],
      body: post["body"],
      created_at: post["createdAt"],
      updated_at: post["updatedAt"],
      likes: post["likes"] || [],
      comments: post["comments"] || []
    }
  rescue JSON::ParserError => e
    raise Error, "Invalid JSON response: #{e.message}"
  end

  def parse_comment_response(body)
    data = JSON.parse(body)
    comment = data.dig("comments")

    unless comment && comment["id"]
      raise Error, "Invalid comment response format"
    end

    {
      id: comment["id"],
      body: comment["body"],
      created_at: comment["createdAt"],
      updated_at: comment["updatedAt"]
    }
  rescue JSON::ParserError => e
    raise Error, "Invalid JSON response: #{e.message}"
  end
end
