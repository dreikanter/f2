module TitleExtractor
  # Suggests a feed title for an X/Twitter account. Prefers the account's
  # display name from the fetched page's og:title, falling back to the
  # @handle from the input.
  class TwitterTitleExtractor < Base
    PROFILE_URL = %r{\A(?:www\.|mobile\.)?(?:twitter|x)\.com/}i

    def title
      og_title.presence || account_handle(PROFILE_URL).presence
    end
  end
end
