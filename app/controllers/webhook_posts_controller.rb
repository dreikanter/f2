# Ingress for webhook feeds (spec 006 §§2-3): POST /hooks/:token accepts one
# post per request and feeds it into the standard publish pipeline. This is a
# deliberately narrow API controller: it has no session, browser gate, CSRF
# surface, or HTML response path. The secret URL itself is the credential.
class WebhookPostsController < ActionController::API
  wrap_parameters false

  # Far above any legitimate post. The request body is read only up to this
  # limit plus one byte, so chunked requests and false Content-Length headers
  # cannot bypass the cap or force an unbounded read before parsing.
  MAX_BODY_BYTES = 128.kilobytes

  # SecureRandom.urlsafe_base64(32) produces 43 unpadded URL-safe characters.
  # Reject malformed path values before deterministic encryption and a DB query.
  TOKEN_PATTERN = /\A[A-Za-z0-9_-]{43}\z/

  # Params parse lazily inside the action, so malformed JSON/form bodies are
  # catchable here — and the contract is JSON in all cases (spec 006 §3).
  rescue_from ActionController::BadRequest, ActionDispatch::Http::Parameters::ParseError,
              with: :reject_bad_request

  def create
    return reject_oversized if oversized_body?

    token = request.path_parameters[:token].to_s
    return reject_unknown_token unless TOKEN_PATTERN.match?(token)

    endpoint = WebhookEndpoint.find_by(encrypted_token: token)
    return reject_unknown_token unless endpoint
    return reject_not_enabled unless endpoint.feed.enabled?

    limit = RateLimit.acquire(:webhook_ingest, subject: endpoint.rate_limit_subject, cost: { request: 1 })
    return reject_throttled(limit) unless limit.allowed?

    respond(WebhookIngestion.new(endpoint: endpoint, payload: payload).call)
  end

  private

  def oversized_body?
    return true if request.content_length.to_i > MAX_BODY_BYTES

    body = request.body
    body.read(MAX_BODY_BYTES + 1).to_s.bytesize > MAX_BODY_BYTES
  ensure
    body&.rewind
  end

  # Request parameters are body-only. Using the merged controller params here
  # would silently discard caller-supplied fields named token/action/etc. rather
  # than letting additionalProperties reject them as the contract requires.
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

  def reject_oversized
    count("payload_too_large")
    head :content_too_large
  end

  def reject_unknown_token
    count("not_found")
    render json: { status: "not_found" }, status: :not_found
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
