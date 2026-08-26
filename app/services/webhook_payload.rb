# One reader for a webhook delivery payload. Both the ingress
# service, which answers a 422 synchronously, and the normalizer, which builds
# the Post later from the stored copy, go through it — so there is no second
# reading of a field to keep in sync with the first.
class WebhookPayload
  def initialize(data)
    @data = data
  end

  def content = data["content"].to_s

  def source_url = data["source_url"].to_s.strip.presence

  def images = Array(data["images"]).map(&:to_s)

  def comments = Array(data["comments"]).map(&:to_s)

  def explicit_uid = data["uid"].to_s.strip

  # Tells a missing uid apart from a blank one: only the latter is an error.
  def uid_given? = data.key?("uid")

  def raw_published_at = data["published_at"].to_s

  def to_h = data

  private

  attr_reader :data
end
