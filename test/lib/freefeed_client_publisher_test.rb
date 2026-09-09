require "test_helper"

class FreefeedClientPublisherTest < ActiveSupport::TestCase
  def setup
    @host = "https://freefeed.net"
    @token = "test_token"
    @client = FreefeedClient.new(host: @host, token: @token)
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

  test "create_post raises ForbiddenError on 403" do
    stub_request(:post, "#{@host}/v4/posts")
      .to_return(status: 403, body: "Forbidden")

    assert_raises(FreefeedClient::ForbiddenError) do
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

    error = assert_raises(FreefeedClient::Error) do
      @client.create_post(body: "Test", feeds: ["testgroup"])
    end
    assert_match(/Invalid JSON response/, error.message)
  end

  test "handles missing required fields in response" do
    stub_request(:post, "#{@host}/v4/posts")
      .to_return(status: 201, body: { "posts" => {} }.to_json)

    assert_raises(FreefeedClient::Error, "Invalid post response format") do
      @client.create_post(body: "Test", feeds: ["testgroup"])
    end
  end
end
