module ProfileMatcher
  # Matches public Telegram channel URLs: t.me/<channel> and t.me/s/<channel>
  # (also telegram.me). Invite links, sticker packs, and other reserved paths
  # are rejected so they fall through to the generic profiles.
  class TelegramProfileMatcher < Base
    input_shape :url
    match_specificity 100

    HOSTS = %w[t.me telegram.me www.t.me].freeze
    RESERVED = %w[s joinchat addstickers addtheme proxy socks setlanguage share login iv].freeze
    USERNAME = /\A[A-Za-z0-9_]{2,64}\z/

    def match?
      return false if input.blank?

      uri = URI.parse(input.strip)
      return false unless HOSTS.include?(uri.host)

      segments = uri.path.to_s.split("/").reject(&:empty?)
      segments.shift if segments.first == "s"
      name = segments.first

      name.present? && !RESERVED.include?(name.downcase) && name.match?(USERNAME)
    rescue URI::InvalidURIError
      false
    end
  end
end
