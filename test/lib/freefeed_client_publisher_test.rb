require "test_helper"

class FreefeedClientPublisherTest < ActiveSupport::TestCase
  def setup
    @host = "https://freefeed.net"
    @token = "test_token"
    @client = FreefeedClient.new(host: @host, token: @token)
  end

  test "create_attachment creates attachment successfully" do
    file_path = Rails.root.join("test", "fixtures", "files", "test_image.jpg")
    FileUtils.mkdir_p(File.dirname(file_path))
    File.write(file_path, "fake image content")

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

    stub_request(:post, "#{@host}/v1/attachments")
      .with(
        headers: {
          "Authorization" => "Bearer #{@token}",
          "Accept" => "application/json",
          "User-Agent" => "FreeFeed-Rails-Client",
          "Content-Type" => /multipart\/form-data/
        }
      )
      .to_return(status: 201, body: attachment_response.to_json)

    result = @client.create_attachment(file_path.to_s)

    assert_equal "attachment123", result[:id]
    assert_equal "https://freefeed.net/attachments/attachment123.jpg", result[:url]
    assert_equal "test_image.jpg", result[:filename]
  ensure
    File.delete(file_path) if File.exist?(file_path)
  end

  test "create_attachment handles file not found" do
    non_existent_file = "/path/to/non/existent/file.jpg"

    assert_raises(Errno::ENOENT) do
      @client.create_attachment(non_existent_file)
    end
  end

  test "create_attachment handles API error" do
    file_path = Rails.root.join("test", "fixtures", "files", "test_image.jpg")
    FileUtils.mkdir_p(File.dirname(file_path))
    File.write(file_path, "fake image content")

    stub_request(:post, "#{@host}/v1/attachments")
      .to_return(status: 400, body: "Bad Request")

    assert_raises(FreefeedClient::Error, "Failed to upload attachment: HTTP 400: Bad Request") do
      @client.create_attachment(file_path.to_s)
    end
  ensure
    File.delete(file_path) if File.exist?(file_path)
  end

  test "create_post creates post successfully" do
    post_response = {
      "posts" => {
        "id" => "post123",
        "body" => "Test post content",
        "createdAt" => "2025-01-01T12:00:00Z",
        "updatedAt" => "2025-01-01T12:00:00Z",
        "likes" => 0,
        "comments" => 0
      }
    }

    stub_request(:post, "#{@host}/v4/posts")
      .with(
        headers: {
          "Authorization" => "Bearer #{@token}",
          "Accept" => "application/json",
          "User-Agent" => "FreeFeed-Rails-Client",
          "Content-Type" => "application/json"
        },
        body: {
          post: {
            body: "Test post content",
            attachments: ["attachment123"]
          },
          meta: {
            feeds: ["testgroup"]
          }
        }.to_json
      )
      .to_return(status: 201, body: post_response.to_json)

    result = @client.create_post(
      body: "Test post content",
      feeds: ["testgroup"],
      attachment_ids: ["attachment123"]
    )

    assert_equal "post123", result[:id]
    assert_equal "Test post content", result[:body]
  end

  test "create_post creates post without attachments" do
    post_response = {
      "posts" => {
        "id" => "post123",
        "body" => "Test post content",
        "createdAt" => "2025-01-01T12:00:00Z",
        "updatedAt" => "2025-01-01T12:00:00Z",
        "likes" => 0,
        "comments" => 0
      }
    }

    stub_request(:post, "#{@host}/v4/posts")
      .with(
        headers: {
          "Authorization" => "Bearer #{@token}",
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

    result = @client.create_post(
      body: "Test post content",
      feeds: ["testgroup"]
    )

    assert_equal "post123", result[:id]
  end

  test "create_post handles API error" do
    stub_request(:post, "#{@host}/v4/posts")
      .to_return(status: 403, body: "Forbidden")

    assert_raises(FreefeedClient::UnauthorizedError) do
      @client.create_post(body: "Test", feeds: ["testgroup"])
    end
  end

  test "create_comment creates comment successfully" do
    comment_response = {
      "comments" => {
        "id" => "comment123",
        "body" => "Test comment",
        "createdAt" => "2025-01-01T12:00:00Z",
        "updatedAt" => "2025-01-01T12:00:00Z"
      }
    }

    stub_request(:post, "#{@host}/v4/comments")
      .with(
        headers: {
          "Authorization" => "Bearer #{@token}",
          "Accept" => "application/json",
          "User-Agent" => "FreeFeed-Rails-Client",
          "Content-Type" => "application/json"
        },
        body: {
          comment: {
            body: "Test comment",
            postId: "post123"
          }
        }.to_json
      )
      .to_return(status: 201, body: comment_response.to_json)

    result = @client.create_comment(
      post_id: "post123",
      body: "Test comment"
    )

    assert_equal "comment123", result[:id]
    assert_equal "Test comment", result[:body]
  end

  test "create_comment handles API error" do
    stub_request(:post, "#{@host}/v4/comments")
      .to_return(status: 404, body: "Post not found")

    assert_raises(FreefeedClient::NotFoundError) do
      @client.create_comment(post_id: "nonexistent", body: "Test comment")
    end
  end

  test "handles unauthorized error" do
    stub_request(:post, "#{@host}/v4/posts")
      .to_return(status: 401, body: "Unauthorized")

    assert_raises(FreefeedClient::UnauthorizedError, "Invalid or expired token") do
      @client.create_post(body: "Test", feeds: ["testgroup"])
    end
  end

  test "handles not found error" do
    stub_request(:post, "#{@host}/v4/comments")
      .to_return(status: 404, body: "Not found")

    assert_raises(FreefeedClient::NotFoundError, "Resource not found") do
      @client.create_comment(post_id: "nonexistent", body: "Test")
    end
  end

  test "handles general HTTP error" do
    stub_request(:post, "#{@host}/v4/posts")
      .to_return(status: 500, body: "Internal Server Error")

    assert_raises(FreefeedClient::Error, "HTTP 500: Internal Server Error") do
      @client.create_post(body: "Test", feeds: ["testgroup"])
    end
  end

  test "handles malformed JSON response" do
    stub_request(:post, "#{@host}/v4/posts")
      .to_return(status: 201, body: "invalid json")

    assert_raises(FreefeedClient::Error, /Invalid JSON response/) do
      @client.create_post(body: "Test", feeds: ["testgroup"])
    end
  end

  test "handles missing required fields in response" do
    stub_request(:post, "#{@host}/v4/posts")
      .to_return(status: 201, body: { "posts" => {} }.to_json)

    assert_raises(FreefeedClient::Error, "Invalid post response format") do
      @client.create_post(body: "Test", feeds: ["testgroup"])
    end
  end
end
