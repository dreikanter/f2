class FeedEntry < ApplicationRecord
  # Where processors put an entry's permalink: webhook and AI payloads use
  # source_url, RSS and JSON Feed use url/link, the social ones url.
  SOURCE_URL_KEYS = %w[source_url url link].freeze

  belongs_to :feed
  has_many :posts, dependent: :destroy

  validates :uid, presence: true
  validates :uid, uniqueness: { scope: :feed_id }

  enum :status, { pending: 0, processed: 1 }

  def source_url
    source_url_candidates.find { |candidate| http_url?(candidate) }
  end

  private

  # RSS guids and AI-minted uids are usually the permalink itself, so the uid is
  # worth a look when raw_data carries none.
  def source_url_candidates
    payload = raw_data.is_a?(Hash) ? raw_data : {}
    SOURCE_URL_KEYS.map { |key| payload[key] } << uid
  end

  # Feed data is external, so a value becomes a link only if it is an absolute
  # http(s) URL. Addressable parses the non-ASCII permalinks URI.parse rejects.
  def http_url?(value)
    uri = Addressable::URI.parse(value.to_s.strip)
    %w[http https].include?(uri.scheme&.downcase) && uri.host.present?
  rescue Addressable::URI::InvalidURIError
    false
  end
end
