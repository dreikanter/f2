require "test_helper"
require "stringio"

class FreefeedClientPublisherTest < ActiveSupport::TestCase
  def setup
    @host = "https://freefeed.net"
    @token = "test_token"
    @client = FreefeedClient.new(host: @host, token: @token)
  end

  test "#create_attachment_from_io should upload multipart content and returns attachment metadata" do
    request = stub_request(:post, "#{@host}/v1/attachments")
      .with(headers: { "Authorization" => "Bearer #{@token}", "Content-Type" => /multipart\/form-data/ }) do |req|
        req.body.include?('name="file"') && req.body.include?("Content-Type: text/plain") && req.body.include?("sample attachment")
      end
      .to_return(status: 201, body: { attachments: {
        id: "attachment123", url: "https://example.com/attachment.txt", fileName: "attachment.txt",
        fileSize: 17, mediaType: "text/plain"
      } }.to_json)

    result = @client.create_attachment_from_io(StringIO.new("sample attachment"), content_type: "text/plain")

    assert_equal({ id: "attachment123", url: "https://example.com/attachment.txt", thumbnail_url: nil,
                   filename: "attachment.txt", file_size: 17, media_type: "text/plain" }, result)
    assert_requested request, times: 1
  end

  test "#create_attachment_from_io should preserve API errors" do
    stub_request(:post, "#{@host}/v1/attachments")
      .to_return(status: 400, body: { err: "Unsupported attachment" }.to_json)

    error = assert_raises(FreefeedClient::BadRequestError) do
      @client.create_attachment_from_io(StringIO.new("sample attachment"), content_type: "text/plain")
    end

    assert_equal "Unsupported attachment", error.message
  end

  test "#create_attachment_from_io should preserve the server's payload-too-large message" do
    stub_request(:post, "#{@host}/v1/attachments")
      .to_return(status: 413, body: { err: "File exceeds the 10 MB upload limit" }.to_json)

    error = assert_raises(FreefeedClient::PayloadTooLargeError) do
      @client.create_attachment_from_io(StringIO.new("sample attachment"), content_type: "text/plain")
    end

    assert_equal "File exceeds the 10 MB upload limit", error.message
  end

  test "#create_post should create post successfully" do
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

  test "#create_post should create post without attachments" do
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

  test "#create_post should raise ForbiddenError on 403" do
    stub_request(:post, "#{@host}/v4/posts")
      .to_return(status: 403, body: "Forbidden")

    assert_raises(FreefeedClient::ForbiddenError) do
      @client.create_post(body: "Test", feeds: ["testgroup"])
    end
  end

  test "#create_comment should create comment successfully" do
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

  test "#create_comment should handle API error" do
    stub_request(:post, "#{@host}/v4/comments")
      .to_return(status: 404, body: "Post not found")

    assert_raises(FreefeedClient::NotFoundError) do
      @client.create_comment(post_id: "nonexistent", body: "Test comment")
    end
  end

  test "#create_post should handle an unauthorized error" do
    stub_request(:post, "#{@host}/v4/posts")
      .to_return(status: 401, body: "Unauthorized")

    assert_raises(FreefeedClient::UnauthorizedError, "Invalid or expired token") do
      @client.create_post(body: "Test", feeds: ["testgroup"])
    end
  end

  test "#create_comment should handle a not found error" do
    stub_request(:post, "#{@host}/v4/comments")
      .to_return(status: 404, body: "Not found")

    assert_raises(FreefeedClient::NotFoundError, "Resource not found") do
      @client.create_comment(post_id: "nonexistent", body: "Test")
    end
  end

  test "#create_post should handle a general HTTP error" do
    stub_request(:post, "#{@host}/v4/posts")
      .to_return(status: 500, body: "Internal Server Error")

    assert_raises(FreefeedClient::Error, "HTTP 500: Internal Server Error") do
      @client.create_post(body: "Test", feeds: ["testgroup"])
    end
  end

  test "#create_post should handle a malformed JSON response" do
    stub_request(:post, "#{@host}/v4/posts")
      .to_return(status: 201, body: "invalid json")

    error = assert_raises(FreefeedClient::Error) do
      @client.create_post(body: "Test", feeds: ["testgroup"])
    end
    assert_match(/Invalid JSON response/, error.message)
  end

  test "#create_post should handle missing required fields in the response" do
    stub_request(:post, "#{@host}/v4/posts")
      .to_return(status: 201, body: { "posts" => {} }.to_json)

    assert_raises(FreefeedClient::Error, "Invalid post response format") do
      @client.create_post(body: "Test", feeds: ["testgroup"])
    end
  end
end
