require "addressable/uri"

# Ingests one webhook delivery into the existing pipeline (spec 006 §§3-4):
# validate the payload, resolve its uid, run it through the profile normalizer,
# then persist FeedEntry + FeedEntryUid + Post in a single transaction and kick
# the publish chain. A payload that fails validation persists nothing — the
# synchronous 422 is the rejection record, so a corrected retry goes through.
class WebhookIngestion
  include HtmlTextUtils

  MAX_LIST_ITEMS = 8
  SUPPORTED_PUBLISHED_AT_YEARS = (1..9999).freeze

  # Caps on images/comments are load-bearing: publishing costs
  # 1 + comments + images FreeFeed POSTs against a burst capacity of 20, and
  # PostPublishJob permanently fails any post whose cost exceeds capacity.
  # 1 + 8 + 8 = 17 keeps every accepted delivery publishable.
  PAYLOAD_SCHEMA = {
    "type" => "object",
    "properties" => {
      "content" => { "type" => "string" },
      "source_url" => { "type" => "string", "maxLength" => Post::MAX_URL_LENGTH },
      "images" => {
        "type" => "array",
        "items" => { "type" => "string" },
        "maxItems" => MAX_LIST_ITEMS
      },
      "comments" => {
        "type" => "array",
        "items" => { "type" => "string" },
        "maxItems" => MAX_LIST_ITEMS
      },
      "uid" => { "type" => "string", "minLength" => 1, "maxLength" => 255 },
      "published_at" => { "type" => "string" }
    },
    "additionalProperties" => false
  }.freeze

  Result = Data.define(:status, :uid, :errors, :warnings) do
    def enqueued? = status == :enqueued
    def duplicate? = status == :duplicate
    def invalid? = status == :invalid
  end

  def initialize(endpoint:, payload:)
    @endpoint = endpoint
    @feed = endpoint.feed
    @payload = WebhookPayload.new(payload)
  end

  def call
    errors = validate_payload
    return invalid(errors) if errors.any?
    return duplicate if already_ingested?

    post = normalized_post
    return invalid(post.validation_errors) if post.rejected?

    persist!(post)
    PostPublishJob.perform_later(feed.id)
    Result.new(status: :enqueued, uid: uid, errors: [], warnings: warnings)
  rescue ActiveRecord::RecordNotUnique
    # Two concurrent deliveries of one uid can both pass the pre-insert check;
    # the (feed_id, uid) unique index arbitrates, and the loser gets the same
    # honest answer as the sequential case.
    duplicate
  end

  private

  attr_reader :endpoint, :feed, :payload

  delegate :content, :source_url, :images, :explicit_uid, :raw_published_at, to: :payload

  def validate_payload
    errors = schema_errors
    return errors if errors.any?

    errors = null_byte_errors
    return errors if errors.any?

    errors << "no_content_or_images" if content.blank? && images.empty?
    errors << "uid must not be blank" if payload.uid_given? && explicit_uid.blank?
    errors << "source_url must be an absolute http(s) URL" if source_url.present? && !http_url?(source_url)
    images.each_with_index do |url, index|
      errors << "images/#{index} must be a public http(s) URL" unless PublicUrl.safe?(url)
    end
    if raw_published_at.present? && !supported_published_at?
      errors << "published_at must be an ISO 8601 timestamp"
    end
    errors
  end

  def schema_errors
    JSONSchemer.schema(PAYLOAD_SCHEMA).validate(payload.to_h).map do |error|
      pointer = error["data_pointer"].to_s
      pointer.empty? ? error["error"] : "#{pointer} #{error['error']}"
    end
  end

  # PostgreSQL text/jsonb values cannot contain a zero byte. Reject it at the
  # request boundary instead of letting an otherwise valid payload fail during
  # persistence with a 500.
  def null_byte_errors
    payload.to_h.each_with_object([]) do |(key, value), errors|
      if value.is_a?(String)
        errors << "#{key} must not contain null bytes" if value.include?("\0")
      elsif value.is_a?(Array)
        value.each_with_index do |item, index|
          errors << "#{key}/#{index} must not contain null bytes" if item.include?("\0")
        end
      end
    end
  end

  def already_ingested?
    FeedEntryUid.exists?(feed_id: feed.id, uid: uid)
  end

  # Normalizers only build objects, so the entry can be normalized before it is
  # saved (the preview workflow does the same). A rejected payload then leaves
  # nothing behind because nothing was written yet.
  def normalized_post
    entry = feed.feed_entries.new(uid: uid, published_at: published_at, raw_data: payload.to_h, status: :processed)
    feed.normalizer_instance(entry).normalize
  end

  def persist!(post)
    ActiveRecord::Base.transaction do
      post.feed_entry.save!
      FeedEntryUid.create!(feed: feed, uid: uid, imported_at: Time.current)
      post.save!
      # SQL-side increment: concurrent deliveries must not lose counts to a
      # stale read-modify-write.
      WebhookEndpoint.update_counters(endpoint.id, received_count: 1, touch: :last_received_at)
    end
  end

  # Percent-encoding during uid normalization can inflate a multibyte URL well
  # past its schema-checked length; past this cap the uid would overflow the
  # (feed_id, uid) btree index rows, so such a URL loses its identity role and
  # the delivery falls back to a random uid instead of a 500.
  MAX_URL_UID_BYTES = 2048

  # Uid precedence (spec 006 §4): explicit idempotency key, then the permalink
  # normalized exactly like pull feeds', then a random uuid (each request is a
  # new post; callers with retrying pipelines should pass uid).
  def resolve_uid
    return explicit_uid if explicit_uid.present?

    from_url = Uid::Resolver.from_url(source_url)
    return SecureRandom.uuid if from_url.nil? || from_url.bytesize > MAX_URL_UID_BYTES

    from_url
  end

  def uid
    @uid ||= resolve_uid
  end

  def duplicate
    endpoint.touch(:last_received_at)
    Result.new(status: :duplicate, uid: uid, errors: [], warnings: [])
  end

  def invalid(errors)
    Result.new(status: :invalid, uid: nil, errors: errors, warnings: [])
  end

  def parsed_published_at
    return @parsed_published_at if defined?(@parsed_published_at)

    @parsed_published_at = Time.iso8601(raw_published_at)
  rescue ArgumentError
    @parsed_published_at = nil
  end

  def supported_published_at?
    parsed_published_at && SUPPORTED_PUBLISHED_AT_YEARS.cover?(parsed_published_at.year)
  end

  def published_at
    value = parsed_published_at
    value.nil? || value > Time.current ? Time.current : value
  end

  # Lenient like Uid::Resolver: an IDN/multibyte permalink is a valid source,
  # so retry with Addressable's encoding before rejecting.
  def http_url?(url)
    uri = begin
      URI.parse(url)
    rescue URI::InvalidURIError
      URI.parse(Addressable::URI.parse(url).normalize.to_s)
    end

    uri.is_a?(URI::HTTP) && uri.host.present?
  rescue Addressable::URI::InvalidURIError, URI::InvalidURIError
    false
  end

  # Length never fails a request — the normalizer truncates instead — but the
  # caller deserves to know.
  def warnings
    content.present? && content.length > content_fit_limit(source_url) ? ["content_truncated"] : []
  end
end
