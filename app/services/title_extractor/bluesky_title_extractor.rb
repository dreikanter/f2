module TitleExtractor
  # Suggests a feed title for a Bluesky account. Prefers the account's
  # display name from the fetched page's og:title, falling back to the
  # @handle taken from the profile URL.
  class BlueskyTitleExtractor < Base
    def title
      og_title.presence || handle.presence
    end

    private

    def handle
      name = input.to_s.strip.sub(%r{\Ahttps?://}i, "")
                  .sub(%r{\A(?:www\.)?bsky\.app/profile/}i, "")
                  .split("/").first.to_s
      name.empty? ? "" : "@#{name}"
    end
  end
end
