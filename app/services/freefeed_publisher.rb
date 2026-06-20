# Publishes posts to FreeFeed using the Post record data.
# Handles attachment uploads, post creation, and comment creation.
#
class FreefeedPublisher
  class Error < StandardError; end
  class ValidationError < Error; end
  class PublishError < Error; end
  # Source content couldn't be fetched (e.g. an attachment URL returns 404). An
  # expected external condition, not an app fault: the job fails the post and
  # moves on without paging error tracking. See PostPublishJob.
  class SourceContentError < PublishError; end
  # The feed's target group can no longer be posted to: the token lost posting
  # permission (group went private/restricted, user removed) or the group was
  # deleted/renamed. The token itself is fine, so only this feed is affected; the
  # job disables it and records why. #reason is a deterministic, UI-safe code (see
  # REASONS); #server_message keeps FreeFeed's raw text for diagnostics only and
  # must never be shown to users. See PostPublishJob.
  class TargetGroupUnavailableError < PublishError
    # Posting was rejected for this destination (lost access / restricted group).
    POSTING_DENIED = :posting_denied
    # The destination group no longer exists (deleted or renamed).
    GROUP_NOT_FOUND = :group_not_found

    attr_reader :reason, :server_message

    def initialize(reason:, server_message: nil)
      @reason = reason
      @server_message = server_message
      super("Target group unavailable (#{reason})")
    end
  end

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

    # Persist the id (marking the post published) before comments, so a retry
    # can't re-create the post. Comments are best-effort: a 429 on a comment
    # leaves the post published and drops the rest — predictable, never
    # duplicated, possibly incomplete. (A non-throttle comment error fails the
    # post instead; see PostPublishJob.) Accepted for now; atomic/resumable
    # publishing is the real fix (revisit). Reserving the whole cost up front
    # (the POST-burst cap) keeps our own limiter from throttling mid-publish, so
    # only a rare server 429 reaches here.
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
    raise SourceContentError, "Failed to upload attachments: #{e.message}"
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
  rescue FreefeedClient::ForbiddenError => e
    raise TargetGroupUnavailableError.new(
      reason: TargetGroupUnavailableError::POSTING_DENIED,
      server_message: e.message
    )
  rescue FreefeedClient::NotFoundError => e
    raise TargetGroupUnavailableError.new(
      reason: TargetGroupUnavailableError::GROUP_NOT_FOUND,
      server_message: e.message
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
        body: Post.clamp_comment(comment_text)
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
    post.update!(freefeed_post_id: freefeed_post_id, status: :published, reposted_at: Time.current)
  rescue => e
    raise PublishError, "Failed to update post status: #{e.message}"
  end
end
