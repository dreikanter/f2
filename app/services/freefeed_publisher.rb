# Publishes posts to FreeFeed using the Post record data.
# Handles attachment uploads, post creation, and comment creation.
#
class FreefeedPublisher
  class Error < StandardError; end
  class ValidationError < Error; end
  class PublishError < Error; end

  attr_reader :post

  def initialize(post)
    @post = post
    validate_post!
  end

  # Publish the post to FreeFeed
  # @return [String] the FreeFeed post ID
  def publish
    # Idempotency guard: if the post already has a FreeFeed id it was created on a
    # previous run, so skip it. This is what stops a 429 raised *after* the post
    # was created (e.g. on a comment) from re-creating the post when the job retries.
    return post.freefeed_post_id if already_published?

    attachment_ids = upload_attachments
    freefeed_post = create_freefeed_post(attachment_ids)
    freefeed_post_id = freefeed_post[:id]

    # Persist the id (and mark the post published) before creating comments so a
    # retry can never re-create the post. Comments are therefore best-effort: if
    # FreeFeed throttles (429) or errors part-way through, the post is already
    # published, the publish chain advances, and the remaining comments are
    # dropped rather than retried. The result is predictable and never
    # duplicated, but the comment set may be incomplete.
    #
    # NOTE: accepted best-effort behaviour for now; full atomic or comment-level
    # resumable publishing is a future improvement (revisit). It is also why a
    # post is capped at the POST bucket's burst (see PostPublishJob#within_capacity?):
    # the whole cost is reserved up front so our own limiter never throttles
    # mid-publish, leaving only a rare server-side 429 to land here, which this
    # path tolerates safely.
    update_post_with_freefeed_id(freefeed_post_id)
    create_comments(freefeed_post_id)

    freefeed_post_id
  rescue FreefeedClient::UnauthorizedError
    raise # propagate so the workflow can disable the token and related feeds
  rescue FreefeedClient::Error => e
    raise PublishError, "Failed to publish to FreeFeed: #{e.message}"
  end

  private

  def validate_post!
    raise ValidationError, "Post is required" unless post
    raise ValidationError, "Post feed is required" unless post.feed
    raise ValidationError, "Post feed access token is required" unless post.feed.access_token
    raise ValidationError, "Post feed access token is inactive" unless post.feed.access_token.active?
    raise ValidationError, "Post feed target group is required" unless post.feed.target_group
    raise ValidationError, "Post content is required" unless post.content.present?
  end

  def client
    @client ||= post.feed.access_token.build_client
  end

  def already_published?
    post.freefeed_post_id.present?
  end

  def upload_attachments
    return [] if post.attachment_urls.blank?

    post.attachment_urls.map do |url|
      io, content_type = FileBuffer.new.load(url)
      attachment = client.create_attachment_from_io(io, content_type: content_type)
      attachment[:id]
    end
  rescue RateLimit::Throttled
    raise # let the job reschedule; don't bury it as a publish failure
  rescue FreefeedClient::UnauthorizedError
    raise
  rescue FileBuffer::Error => e
    raise PublishError, "Failed to upload attachments: #{e.message}"
  rescue => e
    raise PublishError, "Failed to upload attachments: #{e.message}"
  end

  def create_freefeed_post(attachment_ids)
    client.create_post(
      body: post.content,
      feeds: [post.feed.target_group],
      attachment_ids: attachment_ids
    )
  rescue RateLimit::Throttled
    raise
  rescue FreefeedClient::UnauthorizedError
    raise
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
  rescue RateLimit::Throttled
    raise
  rescue FreefeedClient::UnauthorizedError
    raise
  rescue => e
    raise PublishError, "Failed to create comments: #{e.message}"
  end

  def update_post_with_freefeed_id(freefeed_post_id)
    post.update!(freefeed_post_id: freefeed_post_id, status: :published)
  rescue => e
    raise PublishError, "Failed to update post status: #{e.message}"
  end
end
