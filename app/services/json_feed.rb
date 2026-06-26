# Shared knowledge of the JSON Feed format (https://jsonfeed.org), used by
# both the profile matcher (sniffing a fetched body) and the processor
# (recognizing a parsed payload) so the two stay in lockstep.
module JsonFeed
  # The `version` field is the spec URL, e.g. https://jsonfeed.org/version/1.1.
  # Anchored to the canonical host and path so a lookalike like
  # https://evil.com/jsonfeed.org/version/1 can't slip through.
  VERSION_URL = %r{\Ahttps?://jsonfeed\.org/version/\d}

  module_function

  # Whether a parsed payload is a JSON Feed: a JSON object whose `version` is
  # the spec URL and which carries the required `title` (string) and `items`
  # (array) fields (https://jsonfeed.org/version/1.1).
  def feed?(data)
    data.is_a?(Hash) &&
      data["version"].is_a?(String) && data["version"].match?(VERSION_URL) &&
      data["title"].is_a?(String) &&
      data["items"].is_a?(Array)
  end
end
