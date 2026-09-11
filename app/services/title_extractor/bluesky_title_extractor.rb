module TitleExtractor
  # Suggests a feed title for a Bluesky account. Prefers the account's
  # display name from the fetched page's og:title, falling back to the
  # @handle taken from the profile URL.
  class BlueskyTitleExtractor < Base
    PROFILE_URL = %r{\A(?:www\.)?bsky\.app/profile/}i

    def title
      og_title.presence || account_handle(PROFILE_URL).presence
    end
  end
end
