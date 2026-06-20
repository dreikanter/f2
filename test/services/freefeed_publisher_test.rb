require "test_helper"

class FreefeedPublisherTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  def access_token
    @access_token ||= create(:access_token, user: user, status: :active)
  end

  def feed
    @feed ||= create(:feed, user: user, access_token: access_token, feed_profile_key: "rss", target_group: "testgroup")
  end

  def feed_entry
    @feed_entry ||= create(:feed_entry, feed: feed)
  end

  def post_with_content(content, **attributes)
    create(:post, {
      feed: feed,
      feed_entry: feed_entry,
      content: content,
      attachment_urls: [],
      comments: []
    }.merge(attributes))
  end

  test "#initialize should set post and client" do
    post = post_with_content("Test content")
    service = FreefeedPublisher.new(post)

    assert_equal post, service.post
  end

  test "#initialize should raise when post is missing" do
    assert_raises(FreefeedPublisher::ValidationError, "Post is required") do
      FreefeedPublisher.new(nil)
    end
  end

  test "#initialize should raise when post has no feed" do
    post = build(:post, feed: nil)

    assert_raises(FreefeedPublisher::ValidationError, "Post feed is required") do
      FreefeedPublisher.new(post)
    end
  end

  test "#initialize should raise when feed lacks access token" do
    feed = create(:feed, :without_access_token, user: user, feed_profile_key: "rss", state: :disabled)
    post = create(:post, feed: feed, feed_entry: feed_entry)

    error = assert_raises(FreefeedPublisher::ValidationError) do
      FreefeedPublisher.new(post)
    end
    assert_equal "Post feed access token is required", error.message
  end

  test "#initialize should raise when feed lacks target group" do
    feed = create(:feed, user: user, access_token: access_token, feed_profile_key: "rss", target_group: nil, state: :disabled)
    post = create(:post, feed: feed, feed_entry: feed_entry)

    error = assert_raises(FreefeedPublisher::ValidationError) do
      FreefeedPublisher.new(post)
    end
    assert_equal "Post feed target group is required", error.message
  end

  test "#initialize should raise when post lacks content" do
    post = post_with_content("")

    error = assert_raises(FreefeedPublisher::ValidationError) do
      FreefeedPublisher.new(post)
    end
    assert_equal "Post content is required", error.message
  end

  test "#initialize should raise when access token inactive" do
    inactive_token = create(:access_token, user: user, status: :inactive)
    feed_with_inactive_token = create(:feed, user: user, access_token: inactive_token, feed_profile_key: "rss", target_group: "testgroup")
    post = create(:post, feed: feed_with_inactive_token, feed_entry: feed_entry, content: "Test content")

    error = assert_raises(FreefeedPublisher::ValidationError) do
      FreefeedPublisher.new(post)
    end

    assert_equal "Post feed access token is inactive", error.message
  end

  test "#publish should re-raise RateLimit::Throttled instead of wrapping it" do
    post = post_with_content("Test post content")
    stub_request(:post, "#{access_token.host}/v4/posts").to_return(status: 429, headers: { "Retry-After" => "30" })

    RateLimit.stub(:penalize, ->(*, **) { }) do
      assert_raises(RateLimit::Throttled) { FreefeedPublisher.new(post).publish }
    end
  end

  test "#publish should re-raise RateLimit::Throttled when an attachment upload is throttled" do
    file_path = file_fixture("test_image.jpg")
    post = post_with_content("Post with image", attachment_urls: [file_path.to_s])
    stub_request(:post, "#{access_token.host}/v1/attachments").to_return(status: 429, headers: { "Retry-After" => "30" })

    RateLimit.stub(:penalize, ->(*, **) { }) do
      assert_raises(RateLimit::Throttled) { FreefeedPublisher.new(post).publish }
    end
  end

  test "#publish should re-raise RateLimit::Throttled when a comment is throttled" do
    post = post_with_content("Post with comment", comments: ["hello"])
    stub_request(:post, "#{access_token.host}/v4/posts")
      .to_return(status: 201, body: { posts: { id: "freefeed_post_123" } }.to_json)
    stub_request(:post, "#{access_token.host}/v4/comments").to_return(status: 429, headers: { "Retry-After" => "30" })

    RateLimit.stub(:penalize, ->(*, **) { }) do
      assert_raises(RateLimit::Throttled) { FreefeedPublisher.new(post).publish }
    end
  end

  test "#publish should persist the post id before comments so a comment 429 can't duplicate the post" do
    post = post_with_content("Post with comment", comments: ["hello"])
    post_stub = stub_request(:post, "#{access_token.host}/v4/posts")
      .to_return(status: 201, body: { posts: { id: "freefeed_post_123" } }.to_json)
    stub_request(:post, "#{access_token.host}/v4/comments").to_return(status: 429, headers: { "Retry-After" => "30" })

    RateLimit.stub(:penalize, ->(*, **) { }) do
      assert_raises(RateLimit::Throttled) { FreefeedPublisher.new(post).publish }
    end

    # The post was recorded despite the throttle, so it won't be re-created.
    assert_equal "freefeed_post_123", post.reload.freefeed_post_id
    assert_predicate post, :published?

    # A retry (already published) makes no further create-post call.
    assert_equal "freefeed_post_123", FreefeedPublisher.new(post).publish
    assert_requested post_stub, times: 1
  end

  test "#publish should create post without attachments or comments" do
    post = post_with_content("Test post content")

    # Mock FreeFeed API responses
    post_response = {
      "posts" => {
        "id" => "freefeed_post_123",
        "body" => "Test post content",
        "createdAt" => "2025-01-01T12:00:00Z",
        "updatedAt" => "2025-01-01T12:00:00Z",
        "likes" => 0,
        "comments" => 0
      }
    }

    stub_request(:post, "#{access_token.host}/v4/posts")
      .with(
        headers: {
          "Authorization" => "Bearer #{access_token.encrypted_token}",
          "Accept" => "application/json",
          "Content-Type" => "application/json"
        },
        body: {
          post: {
            body: "Test post content"
          },
          meta: {
            feeds: ["testgroup"]
          }
        }.to_json
      )
      .to_return(status: 201, body: post_response.to_json)

    service = FreefeedPublisher.new(post)
    freefeed_post_id = service.publish

    assert_equal "freefeed_post_123", freefeed_post_id
    assert_equal "freefeed_post_123", post.reload.freefeed_post_id
    assert_equal "published", post.status
    assert_not_nil post.reposted_at
  end

  test "#publish should upload attachments before publishing" do
    file_path = file_fixture("test_image.jpg")
    post = post_with_content("Post with image", attachment_urls: [file_path.to_s])

    # Mock attachment upload
    attachment_response = {
      "attachments" => {
        "id" => "attachment123",
        "url" => "https://freefeed.net/attachments/attachment123.jpg",
        "thumbnailUrl" => "https://freefeed.net/attachments/attachment123_thumb.jpg",
        "fileName" => "test_image.jpg",
        "fileSize" => 1024,
        "mediaType" => "image"
      }
    }

    stub_request(:post, "#{access_token.host}/v1/attachments")
      .to_return(status: 201, body: attachment_response.to_json)

    # Mock post creation
    post_response = {
      "posts" => {
        "id" => "freefeed_post_123",
        "body" => "Post with image",
        "createdAt" => "2025-01-01T12:00:00Z",
        "updatedAt" => "2025-01-01T12:00:00Z",
        "likes" => 0,
        "comments" => 0
      }
    }

    stub_request(:post, "#{access_token.host}/v4/posts")
      .with(
        headers: {
          "Authorization" => "Bearer #{access_token.encrypted_token}",
          "Accept" => "application/json",
          "Content-Type" => "application/json"
        },
        body: {
          post: {
            body: "Post with image",
            attachments: ["attachment123"]
          },
          meta: {
            feeds: ["testgroup"]
          }
        }.to_json
      )
      .to_return(status: 201, body: post_response.to_json)

    service = FreefeedPublisher.new(post)
    freefeed_post_id = service.publish

    assert_equal "freefeed_post_123", freefeed_post_id
    assert_equal "freefeed_post_123", post.reload.freefeed_post_id
    assert_equal "published", post.status
  end

  test "#publish should create comments after publishing post" do
    post = post_with_content("Post with comments", comments: ["First comment", "Second comment"])

    # Mock post creation
    post_response = {
      "posts" => {
        "id" => "freefeed_post_123",
        "body" => "Post with comments",
        "createdAt" => "2025-01-01T12:00:00Z",
        "updatedAt" => "2025-01-01T12:00:00Z",
        "likes" => 0,
        "comments" => 0
      }
    }

    stub_request(:post, "#{access_token.host}/v4/posts")
      .with(
        headers: {
          "Authorization" => "Bearer #{access_token.encrypted_token}",
          "Accept" => "application/json",
          "Content-Type" => "application/json"
        },
        body: {
          post: {
            body: "Post with comments"
          },
          meta: {
            feeds: ["testgroup"]
          }
        }.to_json
      )
      .to_return(status: 201, body: post_response.to_json)

    # Mock comment creation
    comment_response_1 = {
      "comments" => {
        "id" => "comment123",
        "body" => "First comment",
        "createdAt" => "2025-01-01T12:00:00Z",
        "updatedAt" => "2025-01-01T12:00:00Z"
      }
    }

    comment_response_2 = {
      "comments" => {
        "id" => "comment456",
        "body" => "Second comment",
        "createdAt" => "2025-01-01T12:00:00Z",
        "updatedAt" => "2025-01-01T12:00:00Z"
      }
    }

    stub_request(:post, "#{access_token.host}/v4/comments")
      .with(
        headers: {
          "Authorization" => "Bearer #{access_token.encrypted_token}",
          "Accept" => "application/json",
          "Content-Type" => "application/json"
        },
        body: {
          comment: {
            body: "First comment",
            postId: "freefeed_post_123"
          }
        }.to_json
      )
      .to_return(status: 201, body: comment_response_1.to_json)

    stub_request(:post, "#{access_token.host}/v4/comments")
      .with(
        headers: {
          "Authorization" => "Bearer #{access_token.encrypted_token}",
          "Accept" => "application/json",
          "Content-Type" => "application/json"
        },
        body: {
          comment: {
            body: "Second comment",
            postId: "freefeed_post_123"
          }
        }.to_json
      )
      .to_return(status: 201, body: comment_response_2.to_json)

    service = FreefeedPublisher.new(post)
    freefeed_post_id = service.publish

    assert_equal "freefeed_post_123", freefeed_post_id
  end

  test "#publish should skip blank comments" do
    post = post_with_content("Post with comments", comments: ["First comment", "", "   ", "Second comment"])

    # Mock post creation
    post_response = {
      "posts" => {
        "id" => "freefeed_post_123",
        "body" => "Post with comments",
        "createdAt" => "2025-01-01T12:00:00Z",
        "updatedAt" => "2025-01-01T12:00:00Z",
        "likes" => 0,
        "comments" => 0
      }
    }

    stub_request(:post, "#{access_token.host}/v4/posts")
      .with(
        headers: {
          "Authorization" => "Bearer #{access_token.encrypted_token}",
          "Accept" => "application/json",
          "Content-Type" => "application/json"
        },
        body: {
          post: {
            body: "Post with comments"
          },
          meta: {
            feeds: ["testgroup"]
          }
        }.to_json
      )
      .to_return(status: 201, body: post_response.to_json)

    # Only expect non-blank comments to be created
    stub_request(:post, "#{access_token.host}/v4/comments")
      .with(
        headers: {
          "Authorization" => "Bearer #{access_token.encrypted_token}",
          "Accept" => "application/json",
          "Content-Type" => "application/json"
        },
        body: {
          comment: {
            body: "First comment",
            postId: "freefeed_post_123"
          }
        }.to_json
      )
      .to_return(status: 201, body: { "comments" => { "id" => "comment123" } }.to_json)

    stub_request(:post, "#{access_token.host}/v4/comments")
      .with(
        headers: {
          "Authorization" => "Bearer #{access_token.encrypted_token}",
          "Accept" => "application/json",
          "Content-Type" => "application/json"
        },
        body: {
          comment: {
            body: "Second comment",
            postId: "freefeed_post_123"
          }
        }.to_json
      )
      .to_return(status: 201, body: { "comments" => { "id" => "comment456" } }.to_json)

    service = FreefeedPublisher.new(post)
    service.publish

    # Verify only 2 comment requests were made (not 4)
    assert_requested(:post, "#{access_token.host}/v4/comments", times: 2)
  end

  test "#publish should return existing freefeed_post_id when already published" do
    post = post_with_content("Already published", freefeed_post_id: "existing_id")

    service = FreefeedPublisher.new(post)
    result = service.publish

    assert_equal "existing_id", result
    # Should not make any API calls
    assert_not_requested(:post, "#{access_token.host}/v4/posts")
  end

  test "#publish should propagate FreefeedClient::UnauthorizedError" do
    post = post_with_content("Test content")
    stub_request(:post, "#{access_token.host}/v4/posts").to_return(status: 401)

    assert_raises(FreefeedClient::UnauthorizedError) do
      FreefeedPublisher.new(post).publish
    end
  end

  test "#publish should raise TargetGroupUnavailableError when the group rejects the post" do
    post = post_with_content("Test content")
    stub_request(:post, "#{access_token.host}/v4/posts")
      .to_return(status: 403, body: { err: "You can not post to some of destinations: testgroup" }.to_json)

    error = assert_raises(FreefeedPublisher::TargetGroupUnavailableError) do
      FreefeedPublisher.new(post).publish
    end
    assert_equal "you no longer have permission to post to @testgroup", error.message
    assert_equal "You can not post to some of destinations: testgroup", error.server_message
  end

  test "#publish should raise TargetGroupUnavailableError when the group no longer exists" do
    post = post_with_content("Test content")
    stub_request(:post, "#{access_token.host}/v4/posts")
      .to_return(status: 404, body: { err: "Account 'testgroup' was not found" }.to_json)

    error = assert_raises(FreefeedPublisher::TargetGroupUnavailableError) do
      FreefeedPublisher.new(post).publish
    end
    assert_equal "the group @testgroup no longer exists or was renamed", error.message
    assert_equal "Account 'testgroup' was not found", error.server_message
  end

  test "#publish should raise error when FreeFeed API fails" do
    post = post_with_content("Test content")

    stub_request(:post, "#{@access_token.host}/v4/posts")
      .to_return(status: 500, body: "Internal Server Error")

    service = FreefeedPublisher.new(post)

    assert_raises(FreefeedPublisher::PublishError, /Failed to publish to FreeFeed/) do
      service.publish
    end
  end

  test "#publish should raise error when attachment upload fails" do
    post = post_with_content("Post with image", attachment_urls: ["/nonexistent/file.jpg"])

    service = FreefeedPublisher.new(post)

    assert_raises(FreefeedPublisher::PublishError, /Failed to upload attachments/) do
      service.publish
    end
  end

  test "#publish should truncate an over-long comment before sending it to FreeFeed" do
    long_comment = "a" * (Post::MAX_COMMENT_LENGTH + 100)
    post = post_with_content("body", comments: [long_comment])

    stub_request(:post, "#{access_token.host}/v4/posts")
      .to_return(status: 201, headers: { "Content-Type" => "application/json" },
                 body: { posts: { id: "ff1" } }.to_json)

    sent_bodies = []
    stub_request(:post, "#{access_token.host}/v4/comments").to_return do |request|
      sent_bodies << JSON.parse(request.body).dig("comment", "body")
      { status: 201, headers: { "Content-Type" => "application/json" },
        body: { comments: { id: "c1" } }.to_json }
    end

    FreefeedPublisher.new(post).publish

    assert_equal 1, sent_bodies.length
    assert_equal Post::MAX_COMMENT_LENGTH, sent_bodies.first.length
    assert sent_bodies.first.end_with?("…")
  end

  test "#publish should raise error when comment creation fails" do
    post = post_with_content("Post with comments", comments: ["Test comment"])

    # Mock successful post creation
    post_response = {
      "posts" => {
        "id" => "freefeed_post_123",
        "body" => "Post with comments",
        "createdAt" => "2025-01-01T12:00:00Z",
        "updatedAt" => "2025-01-01T12:00:00Z",
        "likes" => 0,
        "comments" => 0
      }
    }

    stub_request(:post, "#{@access_token.host}/v4/posts")
      .to_return(status: 201, body: post_response.to_json)

    # Mock failed comment creation
    stub_request(:post, "#{@access_token.host}/v4/comments")
      .to_return(status: 500, body: "Internal Server Error")

    service = FreefeedPublisher.new(post)

    assert_raises(FreefeedPublisher::PublishError, /Failed to create comments/) do
      service.publish
    end
  end

  test "#publish should download remote image attachment to memory" do
    image_data = "\xFF\xD8\xFF\xE0fake_jpeg_data"
    image_url = "https://example.com/image.jpg"

    post = post_with_content("Post with remote image", attachment_urls: [image_url])

    # Mock image download
    stub_request(:get, image_url)
      .to_return(status: 200, body: image_data, headers: { "Content-Type" => "image/jpeg" })

    # Mock attachment upload
    attachment_response = {
      "attachments" => {
        "id" => "attachment_123",
        "url" => "#{access_token.host}/attachment_123.jpg",
        "thumbnailUrl" => "#{access_token.host}/attachment_123_thumb.jpg",
        "fileName" => "image.jpg",
        "fileSize" => image_data.length,
        "mediaType" => "image/jpeg"
      }
    }

    stub_request(:post, "#{access_token.host}/v1/attachments")
      .to_return(status: 201, body: attachment_response.to_json)

    # Mock post creation
    post_response = {
      "posts" => {
        "id" => "freefeed_post_123",
        "body" => "Post with remote image",
        "createdAt" => "2025-01-01T12:00:00Z",
        "updatedAt" => "2025-01-01T12:00:00Z",
        "likes" => 0,
        "comments" => 0
      }
    }

    stub_request(:post, "#{@access_token.host}/v4/posts")
      .to_return(status: 201, body: post_response.to_json)

    service = FreefeedPublisher.new(post)
    freefeed_post_id = service.publish

    assert_equal "freefeed_post_123", freefeed_post_id
    assert_requested :get, image_url
    assert_requested :post, "#{access_token.host}/v1/attachments"
  end

  test "#publish should handle image download failure" do
    image_url = "https://example.com/missing.jpg"
    post = post_with_content("Post with missing image", attachment_urls: [image_url])

    # Mock failed image download
    stub_request(:get, image_url)
      .to_return(status: 404, body: "Not Found")

    service = FreefeedPublisher.new(post)

    assert_raises(FreefeedPublisher::PublishError, /Failed to download attachment from #{Regexp.escape(image_url)}/) do
      service.publish
    end
  end

  test "#publish should raise SourceContentError when an attachment cannot be downloaded" do
    image_url = "https://example.com/missing.jpg"
    post = post_with_content("Post with missing image", attachment_urls: [image_url])
    stub_request(:get, image_url).to_return(status: 404, body: "Not Found")

    assert_raises(FreefeedPublisher::SourceContentError) do
      FreefeedPublisher.new(post).publish
    end
  end

  test "#publish should handle local file attachment" do
    # Create a temporary file
    temp_file = Tempfile.new(["test_image", ".jpg"])
    temp_file.binmode
    image_data = "\xFF\xD8\xFF\xE0fake_jpeg_data"
    temp_file.write(image_data)
    temp_file.close

    post = post_with_content("Post with local file", attachment_urls: [temp_file.path])

    # Mock attachment upload
    attachment_response = {
      "attachments" => {
        "id" => "attachment_123",
        "url" => "#{access_token.host}/attachment_123.jpg",
        "thumbnailUrl" => "#{access_token.host}/attachment_123_thumb.jpg",
        "fileName" => "test_image.jpg",
        "fileSize" => image_data.length,
        "mediaType" => "image/jpeg"
      }
    }

    stub_request(:post, "#{access_token.host}/v1/attachments")
      .to_return(status: 201, body: attachment_response.to_json)

    # Mock post creation
    post_response = {
      "posts" => {
        "id" => "freefeed_post_123",
        "body" => "Post with local file",
        "createdAt" => "2025-01-01T12:00:00Z",
        "updatedAt" => "2025-01-01T12:00:00Z",
        "likes" => 0,
        "comments" => 0
      }
    }

    stub_request(:post, "#{@access_token.host}/v4/posts")
      .to_return(status: 201, body: post_response.to_json)

    service = FreefeedPublisher.new(post)
    freefeed_post_id = service.publish

    assert_equal "freefeed_post_123", freefeed_post_id
    assert_requested :post, "#{access_token.host}/v1/attachments"

    # Cleanup
    temp_file.unlink
  end

  test "#publish should handle HTTP client errors during download" do
    image_url = "https://example.com/timeout.jpg"
    post = post_with_content("Post with timeout image", attachment_urls: [image_url])

    # Mock HTTP client error
    stub_request(:get, image_url)
      .to_raise(HttpClient::TimeoutError.new("Request timed out"))

    service = FreefeedPublisher.new(post)

    assert_raises(FreefeedPublisher::PublishError, /Failed to download attachment from #{Regexp.escape(image_url)}: Request timed out/) do
      service.publish
    end
  end
end
