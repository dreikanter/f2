# Public API ingress for creating posts in webhook-backed feeds. Each request
# creates at most one post and enters the standard normalization and publishing
# pipeline. This API-only controller has no session, browser, CSRF, or HTML surface.
class Api::V1::PostsController < ActionController::API
  wrap_parameters false

  MAX_BODY_BYTES = 128.kilobytes
  BEARER_PATTERN = /\ABearer[ \t]+(?<token>\S+)\z/i

  rescue_from ActionController::BadRequest, ActionDispatch::Http::Parameters::ParseError,
              with: :reject_bad_request

  def create
    return reject_unsupported_media_type unless request.media_type == "application/json"

    endpoint = WebhookEndpoint.authenticate(bearer_token)
    return reject_unauthorized unless endpoint
    return reject_not_enabled unless endpoint.feed.enabled?

    limit = RateLimit.acquire(:webhook_ingest, subject: endpoint.rate_limit_subject, cost: { request: 1 })
    return reject_throttled(limit) unless limit.allowed?
    return reject_oversized if oversized_body?

    respond(WebhookIngestion.new(endpoint: endpoint, payload: payload).call)
  end

  private

  def bearer_token
    BEARER_PATTERN.match(request.authorization.to_s)&.[](:token)
  end

  def oversized_body?
    return true if request.content_length.to_i > MAX_BODY_BYTES

    body = request.body
    body.read(MAX_BODY_BYTES + 1).to_s.bytesize > MAX_BODY_BYTES
  ensure
    body&.rewind
  end

  def payload
    request.request_parameters.deep_stringify_keys
  end

  def respond(result)
    count(result.status.to_s)

    case result.status
    when :enqueued
      body = { status: "enqueued", uid: result.uid }
      body[:warnings] = result.warnings if result.warnings.any?
      render json: body, status: :created
    when :duplicate
      render json: { status: "duplicate", uid: result.uid }, status: :ok
    else
      render json: { status: "invalid", errors: result.errors }, status: :unprocessable_entity
    end
  end

  def reject_bad_request(*)
    count("bad_request")
    render json: { status: "bad_request" }, status: :bad_request
  end

  def reject_unsupported_media_type
    count("unsupported_media_type")
    render json: { status: "unsupported_media_type" }, status: :unsupported_media_type
  end

  def reject_oversized
    count("payload_too_large")
    head :content_too_large
  end

  def reject_unauthorized
    count("unauthorized")
    response.set_header("WWW-Authenticate", 'Bearer realm="webhook"')
    render json: { status: "unauthorized" }, status: :unauthorized
  end

  def reject_not_enabled
    count("feed_not_enabled")
    render json: { status: "feed_not_enabled" }, status: :conflict
  end

  def reject_throttled(limit)
    count("throttled")
    response.set_header("Retry-After", limit.retry_after.ceil.to_s)
    render json: { status: "throttled" }, status: :too_many_requests
  end

  def count(status)
    Metrics.increment("webhook_ingest_total", status: status)
  end
end
