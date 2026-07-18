# Ingress for webhook feeds (spec 006 §§2-3): POST /hooks/:token accepts one
# post per request and feeds it into the standard publish pipeline. The secret
# URL is the whole credential — possession is authorization — so session auth
# and CSRF are skipped, same as ResendWebhooksController.
class WebhookPostsController < ApplicationController
  allow_unauthenticated_access
  skip_forgery_protection
  wrap_parameters false

  # Far above any legitimate post; checked before any parsing (spec 006 §6).
  MAX_BODY_BYTES = 128.kilobytes

  RESERVED_KEYS = %w[token controller action format].freeze

  # Params parse lazily inside the action, so a malformed JSON body is
  # catchable here — and the contract is JSON in all cases (spec 006 §3).
  rescue_from ActionDispatch::Http::Parameters::ParseError do
    count("bad_request")
    render json: { status: "bad_request" }, status: :bad_request
  end

  def create
    return reject_oversized if request.content_length.to_i > MAX_BODY_BYTES

    endpoint = WebhookEndpoint.find_by(encrypted_token: params[:token].to_s)
    return reject_unknown_token unless endpoint
    return reject_not_enabled unless endpoint.feed.enabled?

    limit = RateLimit.acquire(:webhook_ingest, subject: "webhook_endpoint:#{endpoint.id}", cost: { request: 1 })
    return reject_throttled(limit) unless limit.allowed?

    respond(WebhookIngestion.new(endpoint: endpoint, payload: payload).call)
  end

  private

  # ApplicationController's allow_browser registers an anonymous callback that
  # can't be skipped by name; neutralize the instance hook it dispatches to.
  # A webhook sender's User-Agent says nothing about browser support, and this
  # endpoint must never answer 406.
  def allow_browser(**)
  end

  def payload
    params.to_unsafe_h.except(*RESERVED_KEYS)
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
