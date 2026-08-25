class FeedEntry < ApplicationRecord
  # Where processors put an entry's permalink: webhook and AI payloads use
  # source_url, RSS and JSON Feed use url/link, the social ones url.
  SOURCE_URL_KEYS = %w[source_url url link].freeze

  belongs_to :feed
  has_many :posts, dependent: :destroy

  validates :uid, presence: true
  validates :uid, uniqueness: { scope: :feed_id }

  enum :status, { pending: 0, processed: 1 }

  # The original post URL, when the record makes it plain: a permalink from
  # raw_data, or the uid when it is a link itself (RSS guids and AI-minted uids
  # usually are). Nil when nothing usable is there.
  def source_url
    source_url_candidates.find { |candidate| http_url?(candidate) }
  end

  private

  def source_url_candidates
    payload = raw_data.is_a?(Hash) ? raw_data : {}
    SOURCE_URL_KEYS.map { |key| payload[key] } << uid
  end

  # Feed data is external, so only an absolute http(s) URL counts as a link — a
  # bare guid, an at:// URI, or a javascript: scheme is not one. Addressable
  # parses non-ASCII permalinks that URI.parse rejects.
  def http_url?(value)
    uri = Addressable::URI.parse(value.to_s.strip)
    %w[http https].include?(uri.scheme&.downcase) && uri.host.present?
  rescue Addressable::URI::InvalidURIError
    false
  end
end
