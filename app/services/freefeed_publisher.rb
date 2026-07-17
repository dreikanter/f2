# Publishes posts to FreeFeed using the Post record data.
# Handles attachment uploads, post creation, and comment creation.
#
class FreefeedPublisher
  class Error < StandardError; end
  class ValidationError < Error; end
  class PublishError < Error; end
  class CommentPublishError < PublishError; end

  # Source content couldn't be fetched (e.g. an attachment URL returns 404). An
  # expected external condition, not an app fault: the job fails the post and
  # moves on without paging error tracking. See PostPublishJob.
  class SourceContentError < PublishError; end

  # The target group rejected the post (lost access, restricted, or deleted), but
  # the token still works — so the job disables only this feed, not the token.
  # #reason is a deterministic, UI-safe code (POSTING_DENIED/GROUP_NOT_FOUND);
  # #server_message is FreeFeed's raw text, for diagnostics only.
  class TargetGroupUnavailableError < PublishError
    # Posting was rejected for this destination (lost access / restricted group).
    POSTING_DENIED = :posting_denied
    # The destination group no longer exists (deleted or renamed).
    GROUP_NOT_FOUND = :group_not_found

    # The full reason taxonomy. The event description component derives its
    # known-reason list (and locale copy is keyed) from this, so a new code
    # only needs to be added here and translated.
    REASONS = [POSTING_DENIED, GROUP_NOT_FOUND].freeze

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

  # Publish or resume the post's sequential FreeFeed publication.
  # @return [String] the FreeFeed post ID
  def publish
    publication

    unless already_published?
      attachment_ids = upload_pending_attachments
      freefeed_post = create_freefeed_post(attachment_ids)
      update_post_with_freefeed_id(freefeed_post[:id])
    end

    publish_pending_comments
  rescue FreefeedClient::UnauthorizedError
    raise # propagate so the workflow can disable the token and related feeds
  rescue FreefeedClient::Error => e
    raise PublishError, "Failed to publish to FreeFeed: #{e.message}"
  end

  private

  def publication
    @publication ||= post.post_publication || post.create_post_publication!
  end

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

  def upload_pending_attachments
    post.attachment_urls.drop(publication.attachments_processed_count).each do |url|
      attachment_id = upload_attachment(url)
      attachment_ids = publication.uploaded_attachment_ids.dup
      attachment_ids << attachment_id if attachment_id

      publication.update!(
        attachments_processed_count: publication.attachments_processed_count + 1,
        uploaded_attachment_ids: attachment_ids
      )
    end

    publication.uploaded_attachment_ids
  rescue RateLimit::Throttled
    raise
  rescue FreefeedClient::UnauthorizedError
    raise
  rescue FileBuffer::Error => e
    raise SourceContentError, "Failed to upload attachments: #{e.message}"
  rescue => e
    raise PublishError, "Failed to upload attachments: #{e.message}"
  end

  # A file over the server's upload limit is a source-content problem, not an
  # app fault: skip it and publish the post with the remaining attachments.
  def upload_attachment(url)
    io, content_type = FileBuffer.new.load(url)
    client.create_attachment_from_io(io, content_type: content_type)[:id]
  rescue FreefeedClient::PayloadTooLargeError => e
    Rails.logger.warn "Skipping oversized attachment #{url} for post #{post.id}: #{e.message}"
    nil
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

  def publish_pending_comments
    comments = post.comments.filter_map(&:presence)

    comments.drop(publication.comments_published_count).each do |comment_text|
      create_comment(comment_text)
      publication.increment!(:comments_published_count)
    end

    publication.destroy!
    post.freefeed_post_id
  rescue RateLimit::Throttled
    raise
  rescue FreefeedClient::UnauthorizedError
    raise
  rescue => e
    raise CommentPublishError, "Failed to create comments: #{e.message}"
  end

  def create_comment(comment_text)
    client.create_comment(
      post_id: post.freefeed_post_id,
      body: Post.clamp_comment(comment_text)
    )
  end

  def update_post_with_freefeed_id(freefeed_post_id)
    post.update!(freefeed_post_id: freefeed_post_id, status: :published, reposted_at: Time.current)
  rescue => e
    raise PublishError, "Failed to update post status: #{e.message}"
  end
end
