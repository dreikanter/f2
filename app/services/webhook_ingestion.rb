require "addressable/uri"

# Ingests one webhook delivery into the existing pipeline (spec 006 §§3-4):
# validate the payload, resolve its uid, persist FeedEntry + FeedEntryUid +
# Post through the profile normalizer in a single transaction, then kick the
# publish chain. A payload that fails validation persists nothing — the
# synchronous 422 is the rejection record, so a corrected retry goes through.
class WebhookIngestion
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
    @payload = payload
  end

  def call
    errors = validate_payload
    return invalid(errors) if errors.any?
    return duplicate if already_ingested?

    rejection = ingest!
    return invalid(rejection) if rejection

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

  def validate_payload
    errors = schema_errors
    return errors if errors.any?

    errors = null_byte_errors
    return errors if errors.any?

    errors << "no_content_or_images" if content.blank? && images.empty?
    errors << "uid must not be blank" if payload.key?("uid") && explicit_uid.blank?
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
    JSONSchemer.schema(PAYLOAD_SCHEMA).validate(payload).map do |error|
      pointer = error["data_pointer"].to_s
      pointer.empty? ? error["error"] : "#{pointer} #{error['error']}"
    end
  end

  # PostgreSQL text/jsonb values cannot contain a zero byte. Reject it at the
  # request boundary instead of letting an otherwise valid payload fail during
  # persistence with a 500.
  def null_byte_errors
    payload.each_with_object([]) do |(key, value), errors|
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

  def ingest!
    rejection = nil

    ActiveRecord::Base.transaction do
      entry = feed.feed_entries.create!(uid: uid, published_at: published_at, raw_data: payload, status: :pending)
      FeedEntryUid.create!(feed: feed, uid: uid, imported_at: Time.current)

      post = feed.normalizer_instance(entry).normalize
      if post.rejected?
        rejection = post.validation_errors
        raise ActiveRecord::Rollback
      end

      entry.update!(status: :processed)
      post.save!
      # SQL-side increment: concurrent deliveries must not lose counts to a
      # stale read-modify-write.
      WebhookEndpoint.update_counters(endpoint.id, received_count: 1, touch: :last_received_at)
    end

    rejection
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

    from_url = source_url.present? && Uid::Resolver.call({ "source_url" => source_url }, clock: Time.current)
    from_url = nil if from_url && from_url.bytesize > MAX_URL_UID_BYTES
    from_url.presence || SecureRandom.uuid
  end

  def explicit_uid
    @explicit_uid ||= payload["uid"].to_s.strip
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

  def content
    payload["content"].to_s
  end

  def source_url
    payload["source_url"].to_s.strip.presence
  end

  def images
    Array(payload["images"])
  end

  def raw_published_at
    payload["published_at"].to_s
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
  # caller deserves to know. Mirrors post_content_with_url's fit math.
  def warnings
    content_truncated? ? ["content_truncated"] : []
  end

  def content_truncated?
    return false if content.blank?

    limit = if source_url.nil? || source_url.length > Post::MAX_URL_LENGTH
      Post::MAX_CONTENT_LENGTH
    else
      Post::MAX_CONTENT_LENGTH - HtmlTextUtils::CONTENT_URL_SEPARATOR.length - source_url.length
    end

    content.length > limit
  end
end
