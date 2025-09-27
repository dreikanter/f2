# FreeFeed Publisher
#
# Publishes posts to FreeFeed using the Post record data.
# Handles attachment uploads, post creation, and comment creation.
class FreefeedPublisher
  class Error < StandardError; end
  class ValidationError < Error; end
  class PublishError < Error; end

  attr_reader :post, :client

  def initialize(post)
    @post = post
    validate_post!
    @client = build_client
    @http_client = HttpClient::FaradayAdapter.new
  end

  # Publish the post to FreeFeed
  # @return [String] the FreeFeed post ID
  def publish
    return post.freefeed_post_id if already_published?

    attachment_ids = upload_attachments
    freefeed_post = create_freefeed_post(attachment_ids)
    freefeed_post_id = freefeed_post[:id]
    create_comments(freefeed_post_id)

    update_post_with_freefeed_id(freefeed_post_id)
    freefeed_post_id
  rescue FreefeedClient::Error => e
    raise PublishError, "Failed to publish to FreeFeed: #{e.message}"
  end

  private

  def validate_post!
    raise ValidationError, "Post is required" unless post
    raise ValidationError, "Post feed is required" unless post.feed
    raise ValidationError, "Post feed access token is required" unless post.feed.access_token
    raise ValidationError, "Post feed target group is required" unless post.feed.target_group
    raise ValidationError, "Post content is required" unless post.content.present?
  end

  def build_client
    FreefeedClient.new(
      host: post.feed.access_token.host,
      token: post.feed.access_token.token_value
    )
  end

  def already_published?
    post.freefeed_post_id.present?
  end

  def upload_attachments
    return [] if post.attachment_urls.blank?

    post.attachment_urls.map do |url|
      io, content_type = download_attachment_to_memory(url)
      attachment = client.create_attachment_from_io(io, content_type)
      attachment[:id]
    end
  rescue => e
    raise PublishError, "Failed to upload attachments: #{e.message}"
  end

  def create_freefeed_post(attachment_ids)
    client.create_post(
      body: post.content,
      feeds: [post.feed.target_group],
      attachment_ids: attachment_ids
    )
  rescue => e
    raise PublishError, "Failed to create FreeFeed post: #{e.message}"
  end

  def create_comments(freefeed_post_id)
    return if post.comments.blank?

    post.comments.each do |comment_text|
      next if comment_text.blank?

      client.create_comment(
        post_id: freefeed_post_id,
        body: comment_text
      )
    end
  rescue => e
    raise PublishError, "Failed to create comments: #{e.message}"
  end

  def update_post_with_freefeed_id(freefeed_post_id)
    post.update!(freefeed_post_id: freefeed_post_id, status: :published)
  rescue => e
    raise PublishError, "Failed to update post status: #{e.message}"
  end

  def download_attachment_to_memory(url)
    # If it's already a local file path, read it to memory
    if File.exist?(url)
      content = File.binread(url)
      content_type = MiniMime.lookup_by_filename(url)&.content_type || "application/octet-stream"
      io = StringIO.new(content)
      io.set_encoding(Encoding::BINARY)
      return [io, content_type]
    end

    # Download external URL to memory
    response = @http_client.get(url)

    unless response.success?
      raise PublishError, "Failed to download attachment from #{url}: HTTP #{response.status}"
    end

    # Detect content type from URL or default to image
    uri = URI(url)
    content_type = MiniMime.lookup_by_filename(uri.path)&.content_type || "image/jpeg"

    # Create StringIO from response body
    io = StringIO.new(response.body)
    io.set_encoding(Encoding::BINARY)
    io.rewind

    [io, content_type]
  rescue HttpClient::Error => e
    raise PublishError, "Failed to download attachment from #{url}: #{e.message}"
  rescue => e
    raise PublishError, "Failed to download attachment from #{url}: #{e.message}"
  end
end
