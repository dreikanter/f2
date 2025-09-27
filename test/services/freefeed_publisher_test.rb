require "test_helper"

class FreefeedPublisherTest < ActiveSupport::TestCase
  def setup
    @user = create(:user)
    @access_token = create(:access_token, user: @user, status: :active)
    @feed_profile = create(:feed_profile)
    @feed = create(:feed, user: @user, access_token: @access_token, feed_profile: @feed_profile, target_group: "testgroup")
    @feed_entry = create(:feed_entry, feed: @feed)
  end

  def post_with_content(content, **attributes)
    create(:post, {
      feed: @feed,
      feed_entry: @feed_entry,
      content: content,
      attachment_urls: [],
      comments: []
    }.merge(attributes))
  end

  test "initializes successfully with valid post" do
    post = post_with_content("Test content")
    service = FreefeedPublisher.new(post)

    assert_equal post, service.post
    assert_instance_of FreefeedClient, service.client
  end

  test "raises validation error for missing post" do
    assert_raises(FreefeedPublisher::ValidationError, "Post is required") do
      FreefeedPublisher.new(nil)
    end
  end

  test "raises validation error for post without feed" do
    post = build(:post, feed: nil)

    assert_raises(FreefeedPublisher::ValidationError, "Post feed is required") do
      FreefeedPublisher.new(post)
    end
  end

  test "raises validation error for feed without access token" do
    feed = create(:feed, :without_access_token, user: @user, feed_profile: @feed_profile, state: :disabled)
    post = create(:post, feed: feed, feed_entry: @feed_entry)

    error = assert_raises(FreefeedPublisher::ValidationError) do
      FreefeedPublisher.new(post)
    end
    assert_equal "Post feed access token is required", error.message
  end

  test "raises validation error for feed without target group" do
    feed = create(:feed, user: @user, access_token: @access_token, feed_profile: @feed_profile, target_group: nil, state: :disabled)
    post = create(:post, feed: feed, feed_entry: @feed_entry)

    error = assert_raises(FreefeedPublisher::ValidationError) do
      FreefeedPublisher.new(post)
    end
    assert_equal "Post feed target group is required", error.message
  end

  test "raises validation error for post without content" do
    post = post_with_content("")

    error = assert_raises(FreefeedPublisher::ValidationError) do
      FreefeedPublisher.new(post)
    end
    assert_equal "Post content is required", error.message
  end

  test "publish creates post without attachments or comments" do
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

    stub_request(:post, "#{@access_token.host}/v4/posts")
      .with(
        headers: {
          "Authorization" => "Bearer #{@access_token.token_value}",
          "Accept" => "application/json",
          "User-Agent" => "FreeFeed-Rails-Client",
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
  end

  test "publish creates post with attachments" do
    # Create temporary test file
    file_path = Rails.root.join("test", "fixtures", "files", "test_image.jpg")
    FileUtils.mkdir_p(File.dirname(file_path))
    File.write(file_path, "fake image content")

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

    stub_request(:post, "#{@access_token.host}/v1/attachments")
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

    stub_request(:post, "#{@access_token.host}/v4/posts")
      .with(
        headers: {
          "Authorization" => "Bearer #{@access_token.token_value}",
          "Accept" => "application/json",
          "User-Agent" => "FreeFeed-Rails-Client",
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
  ensure
    File.delete(file_path) if File.exist?(file_path)
  end

  test "publish creates post with comments" do
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

    stub_request(:post, "#{@access_token.host}/v4/posts")
      .with(
        headers: {
          "Authorization" => "Bearer #{@access_token.token_value}",
          "Accept" => "application/json",
          "User-Agent" => "FreeFeed-Rails-Client",
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

    stub_request(:post, "#{@access_token.host}/v4/comments")
      .with(
        headers: {
          "Authorization" => "Bearer #{@access_token.token_value}",
          "Accept" => "application/json",
          "User-Agent" => "FreeFeed-Rails-Client",
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

    stub_request(:post, "#{@access_token.host}/v4/comments")
      .with(
        headers: {
          "Authorization" => "Bearer #{@access_token.token_value}",
          "Accept" => "application/json",
          "User-Agent" => "FreeFeed-Rails-Client",
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

  test "publish skips blank comments" do
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

    stub_request(:post, "#{@access_token.host}/v4/posts")
      .with(
        headers: {
          "Authorization" => "Bearer #{@access_token.token_value}",
          "Accept" => "application/json",
          "User-Agent" => "FreeFeed-Rails-Client",
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
    stub_request(:post, "#{@access_token.host}/v4/comments")
      .with(
        headers: {
          "Authorization" => "Bearer #{@access_token.token_value}",
          "Accept" => "application/json",
          "User-Agent" => "FreeFeed-Rails-Client",
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

    stub_request(:post, "#{@access_token.host}/v4/comments")
      .with(
        headers: {
          "Authorization" => "Bearer #{@access_token.token_value}",
          "Accept" => "application/json",
          "User-Agent" => "FreeFeed-Rails-Client",
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
    assert_requested(:post, "#{@access_token.host}/v4/comments", times: 2)
  end

  test "publish returns existing freefeed_post_id if already published" do
    post = post_with_content("Already published", freefeed_post_id: "existing_id")

    service = FreefeedPublisher.new(post)
    result = service.publish

    assert_equal "existing_id", result
    # Should not make any API calls
    assert_not_requested(:post, "#{@access_token.host}/v4/posts")
  end

  test "publish handles FreeFeed API errors gracefully" do
    post = post_with_content("Test content")

    stub_request(:post, "#{@access_token.host}/v4/posts")
      .to_return(status: 500, body: "Internal Server Error")

    service = FreefeedPublisher.new(post)

    assert_raises(FreefeedPublisher::PublishError, /Failed to publish to FreeFeed/) do
      service.publish
    end
  end

  test "publish handles attachment upload errors" do
    post = post_with_content("Post with image", attachment_urls: ["/nonexistent/file.jpg"])

    service = FreefeedPublisher.new(post)

    assert_raises(FreefeedPublisher::PublishError, /Failed to upload attachments/) do
      service.publish
    end
  end

  test "publish handles comment creation errors" do
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
end
