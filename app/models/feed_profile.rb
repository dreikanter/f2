# Feed profile registry. Each entry describes one input → posts pipeline
# (matcher + parameter shape + loader/processor/normalizer triple).
#
class FeedProfile
  # Shared output shape for AI extraction: the `{ items: [...] }` envelope the
  # LLM loader returns and PassthroughProcessor unpacks.
  UNIVERSAL_OUTPUT_SCHEMA = {
    "type" => "object",
    "properties" => {
      "items" => {
        "type" => "array",
        "items" => {
          "type" => "object",
          "properties" => {
            # The processor derives the uid from source_url. `uid` is
            # accepted only so a stray field from a non-strict provider
            # doesn't fail the schema; it's ignored downstream.
            "uid" => { "type" => "string" },
            "title" => { "type" => "string" },
            "body" => { "type" => "string" },
            "supplementary" => { "type" => "array", "items" => { "type" => "string" } },
            "images" => { "type" => "array", "items" => { "type" => "string" } },
            # An explicit null signals the digest/standing-query regime; a real
            # permalink signals feed-style. The key is always required —
            # a missing key is malformed, not a digest.
            "source_url" => { "type" => ["string", "null"] },
            "published_at" => { "type" => "string" }
          },
          "required" => ["body", "source_url"],
          "additionalProperties" => false
        }
      }
    },
    "required" => ["items"],
    "additionalProperties" => false
  }.freeze

  # Shared parameter shape for URL-sourced profiles.
  URL_PARAMETER_SCHEMA = {
    "type" => "object",
    "properties" => {
      "url" => { "type" => "string", "format" => "uri" }
    },
    "required" => ["url"],
    "additionalProperties" => false
  }.freeze

  # Variant for profiles whose source may be a bare handle (r/name, @channel)
  # rather than a strict URI.
  LOOSE_URL_PARAMETER_SCHEMA = {
    "type" => "object",
    "properties" => {
      "url" => { "type" => "string", "minLength" => 2 }
    },
    "required" => ["url"],
    "additionalProperties" => false
  }.freeze

  PROFILES = {
    "rss" => {
      display_name: "RSS Feed",
      description: "Posts from a site's RSS or Atom feed",
      input_shape: :url,
      depends_on_ai: false,
      scheduled: true,
      matcher: "ProfileMatcher::RssProfileMatcher",
      parameter_schema: URL_PARAMETER_SCHEMA,
      loader: { class: "Loader::HttpLoader", config: {} },
      processor: { class: "Processor::RssProcessor", config: {} },
      normalizer: { class: "Normalizer::RssNormalizer", config: {} },
      title_extractor: "TitleExtractor::RssTitleExtractor"
    },
    "json_feed" => {
      display_name: "JSON Feed",
      description: "Posts from a site's JSON feed (jsonfeed.org)",
      input_shape: :url,
      depends_on_ai: false,
      scheduled: true,
      matcher: "ProfileMatcher::JsonFeedProfileMatcher",
      parameter_schema: URL_PARAMETER_SCHEMA,
      loader: { class: "Loader::HttpLoader", config: {} },
      processor: { class: "Processor::JsonFeedProcessor", config: {} },
      normalizer: { class: "Normalizer::JsonFeedNormalizer", config: {} },
      title_extractor: "TitleExtractor::JsonFeedTitleExtractor"
    },
    "podcast" => {
      display_name: "Podcast",
      description: "Podcast episodes with cover art and show notes",
      input_shape: :url,
      depends_on_ai: false,
      scheduled: true,
      matcher: "ProfileMatcher::PodcastProfileMatcher",
      parameter_schema: URL_PARAMETER_SCHEMA,
      loader: { class: "Loader::HttpLoader", config: {} },
      processor: { class: "Processor::PodcastProcessor", config: {} },
      normalizer: { class: "Normalizer::PodcastNormalizer", config: {} },
      title_extractor: "TitleExtractor::RssTitleExtractor"
    },
    "reddit" => {
      display_name: "Reddit",
      description: "Posts from a subreddit or Reddit user page via RSS",
      input_shape: :url,
      depends_on_ai: false,
      scheduled: true,
      matcher: "ProfileMatcher::RedditProfileMatcher",
      parameter_schema: LOOSE_URL_PARAMETER_SCHEMA,
      loader: { class: "Loader::RedditLoader", config: {} },
      processor: { class: "Processor::RssProcessor", config: {} },
      normalizer: { class: "Normalizer::RedditNormalizer", config: {} },
      title_extractor: "TitleExtractor::RssTitleExtractor"
    },
    "xkcd" => {
      display_name: "XKCD",
      description: "Posts from xkcd.com with the alt text included",
      input_shape: :url,
      depends_on_ai: false,
      scheduled: true,
      matcher: "ProfileMatcher::XkcdProfileMatcher",
      parameter_schema: URL_PARAMETER_SCHEMA,
      loader: { class: "Loader::HttpLoader", config: {} },
      processor: { class: "Processor::RssProcessor", config: {} },
      normalizer: { class: "Normalizer::XkcdNormalizer", config: {} },
      title_extractor: "TitleExtractor::RssTitleExtractor"
    },
    "buni" => {
      display_name: "Buni Comic",
      description: "Wordless Buni comic strips from bunicomic.com",
      input_shape: :url,
      depends_on_ai: false,
      scheduled: true,
      matcher: "ProfileMatcher::BuniProfileMatcher",
      parameter_schema: URL_PARAMETER_SCHEMA,
      loader: { class: "Loader::HttpLoader", config: {} },
      processor: { class: "Processor::RssProcessor", config: {} },
      normalizer: { class: "Normalizer::BuniNormalizer", config: {} },
      title_extractor: "TitleExtractor::RssTitleExtractor"
    },
    "elementy" => {
      display_name: "Elementy",
      description: "Science news from elementy.ru with cover images",
      input_shape: :url,
      depends_on_ai: false,
      scheduled: true,
      matcher: "ProfileMatcher::ElementyProfileMatcher",
      parameter_schema: URL_PARAMETER_SCHEMA,
      loader: { class: "Loader::HttpLoader", config: {} },
      processor: { class: "Processor::RssProcessor", config: {} },
      normalizer: { class: "Normalizer::ElementyNormalizer", config: {} },
      title_extractor: "TitleExtractor::RssTitleExtractor"
    },
    "melodymae" => {
      display_name: "Melody Mae",
      description: "Posts from Melody Mae's plus-size fashion blog at melodymae.co.uk",
      input_shape: :url,
      depends_on_ai: false,
      scheduled: true,
      matcher: "ProfileMatcher::MelodymaeProfileMatcher",
      parameter_schema: URL_PARAMETER_SCHEMA,
      loader: { class: "Loader::HttpLoader", config: {} },
      processor: { class: "Processor::RssProcessor", config: {} },
      normalizer: { class: "Normalizer::MelodymaeNormalizer", config: {} },
      title_extractor: "TitleExtractor::RssTitleExtractor"
    },
    "nextbigfuture" => {
      display_name: "Next Big Future",
      description: "Technology news from nextbigfuture.com with cover images",
      input_shape: :url,
      depends_on_ai: false,
      scheduled: true,
      matcher: "ProfileMatcher::NextbigfutureProfileMatcher",
      parameter_schema: URL_PARAMETER_SCHEMA,
      loader: { class: "Loader::HttpLoader", config: {} },
      processor: { class: "Processor::RssProcessor", config: {} },
      normalizer: { class: "Normalizer::NextbigfutureNormalizer", config: {} },
      title_extractor: "TitleExtractor::RssTitleExtractor"
    },
    "monkeyuser" => {
      display_name: "MonkeyUser",
      description: "MonkeyUser comics for developers",
      input_shape: :url,
      depends_on_ai: false,
      scheduled: true,
      matcher: "ProfileMatcher::MonkeyuserProfileMatcher",
      parameter_schema: URL_PARAMETER_SCHEMA,
      loader: { class: "Loader::HttpLoader", config: {} },
      processor: { class: "Processor::RssProcessor", config: {} },
      normalizer: { class: "Normalizer::MonkeyuserNormalizer", config: {} },
      title_extractor: "TitleExtractor::RssTitleExtractor"
    },
    "lobsters" => {
      display_name: "Lobsters",
      description: "Stories from lobste.rs with a link to the discussion",
      input_shape: :url,
      depends_on_ai: false,
      scheduled: true,
      matcher: "ProfileMatcher::LobstersProfileMatcher",
      parameter_schema: URL_PARAMETER_SCHEMA,
      loader: { class: "Loader::HttpLoader", config: {} },
      processor: { class: "Processor::RssProcessor", config: {} },
      normalizer: { class: "Normalizer::LobstersNormalizer", config: {} },
      title_extractor: "TitleExtractor::RssTitleExtractor"
    },
    "litterbox" => {
      display_name: "Litterbox Comics",
      description: "Family life comics from Litterbox Comics, bonus panels included",
      input_shape: :url,
      depends_on_ai: false,
      scheduled: true,
      matcher: "ProfileMatcher::LitterboxProfileMatcher",
      parameter_schema: URL_PARAMETER_SCHEMA,
      loader: { class: "Loader::HttpLoader", config: {} },
      processor: { class: "Processor::RssProcessor", config: {} },
      normalizer: { class: "Normalizer::LitterboxNormalizer", config: {} },
      title_extractor: "TitleExtractor::RssTitleExtractor"
    },
    "oglaf" => {
      display_name: "Oglaf",
      description: "Comic strips from oglaf.com, multi-page stories included",
      input_shape: :url,
      depends_on_ai: false,
      scheduled: true,
      matcher: "ProfileMatcher::OglafProfileMatcher",
      parameter_schema: URL_PARAMETER_SCHEMA,
      loader: { class: "Loader::HttpLoader", config: {} },
      processor: { class: "Processor::RssProcessor", config: {} },
      normalizer: { class: "Normalizer::OglafNormalizer", config: {} },
      title_extractor: "TitleExtractor::RssTitleExtractor"
    },
    "pluralistic" => {
      display_name: "Pluralistic",
      description: "Cory Doctorow's Pluralistic linkblog with cover images",
      input_shape: :url,
      depends_on_ai: false,
      scheduled: true,
      matcher: "ProfileMatcher::PluralisticProfileMatcher",
      parameter_schema: URL_PARAMETER_SCHEMA,
      loader: { class: "Loader::HttpLoader", config: {} },
      processor: { class: "Processor::RssProcessor", config: {} },
      normalizer: { class: "Normalizer::PluralisticNormalizer", config: {} },
      title_extractor: "TitleExtractor::RssTitleExtractor"
    },
    "smbc" => {
      display_name: "SMBC Comics",
      description: "Saturday Morning Breakfast Cereal comics with the hovertext and hidden panel",
      input_shape: :url,
      depends_on_ai: false,
      scheduled: true,
      matcher: "ProfileMatcher::SmbcProfileMatcher",
      parameter_schema: URL_PARAMETER_SCHEMA,
      loader: { class: "Loader::HttpLoader", config: {} },
      processor: { class: "Processor::RssProcessor", config: {} },
      normalizer: { class: "Normalizer::SmbcNormalizer", config: {} },
      title_extractor: "TitleExtractor::RssTitleExtractor"
    },
    "aerostat" => {
      display_name: "Aerostat",
      description: "Boris Grebenshchikov's Aerostat radio show episodes",
      input_shape: :url,
      depends_on_ai: false,
      scheduled: true,
      matcher: "ProfileMatcher::AerostatProfileMatcher",
      parameter_schema: URL_PARAMETER_SCHEMA,
      loader: { class: "Loader::HttpLoader", config: {} },
      processor: { class: "Processor::AerostatProcessor", config: {} },
      normalizer: { class: "Normalizer::AerostatNormalizer", config: {} },
      title_extractor: "TitleExtractor::RssTitleExtractor"
    },
    "theycantalk" => {
      display_name: "They Can Talk",
      description: "They Can Talk comics about what animals might say",
      input_shape: :url,
      depends_on_ai: false,
      scheduled: true,
      matcher: "ProfileMatcher::TheycantalkProfileMatcher",
      parameter_schema: URL_PARAMETER_SCHEMA,
      loader: { class: "Loader::HttpLoader", config: {} },
      processor: { class: "Processor::RssProcessor", config: {} },
      normalizer: { class: "Normalizer::TheycantalkNormalizer", config: {} },
      title_extractor: "TitleExtractor::RssTitleExtractor"
    },
    "tomorrows" => {
      display_name: "365 Tomorrows",
      description: "Daily flash science fiction from 365tomorrows.com",
      input_shape: :url,
      depends_on_ai: false,
      scheduled: true,
      matcher: "ProfileMatcher::TomorrowsProfileMatcher",
      parameter_schema: URL_PARAMETER_SCHEMA,
      loader: { class: "Loader::HttpLoader", config: {} },
      processor: { class: "Processor::RssProcessor", config: {} },
      normalizer: { class: "Normalizer::TomorrowsNormalizer", config: {} },
      title_extractor: "TitleExtractor::RssTitleExtractor"
    },
    "llm" => {
      display_name: "AI",
      description: "Uses AI to follow and transform web content per a free-form prompt",
      # Accepts anything (a link, several links, or a description); the prompt
      # is the source. The params key is `prompt`, not derived from input_shape.
      # Registers NO matcher: the AI profile is structurally excluded from
      # detection — Mode B selects it directly, detection never can.
      input_shape: :any,
      depends_on_ai: true,
      scheduled: true,
      parameter_schema: {
        "type" => "object",
        "properties" => {
          "prompt" => { "type" => "string", "minLength" => 1, "maxLength" => 2000 }
        },
        "required" => ["prompt"],
        "additionalProperties" => false
      },
      loader: {
        class: "Loader::LlmLoader",
        config: {
          # The task, output contract, and safeguards live in the system
          # prompt (Loader::LlmPrompts). The user's own prompt is a
          # legitimate instruction, so it travels as the user message,
          # distinct from the untrusted web content the model fetches.
          prompt_template: <<~PROMPT,
            Feed request — what to follow and how to present it:

            {{input}}
          PROMPT
          output_schema: UNIVERSAL_OUTPUT_SCHEMA
        }
      },
      processor: { class: "Processor::PassthroughProcessor", config: {} },
      normalizer: { class: "Normalizer::LlmNormalizer", config: {} },
      title_extractor: nil
    },
    "youtube" => {
      display_name: "YouTube",
      description: "Videos from a YouTube channel",
      input_shape: :url,
      depends_on_ai: false,
      scheduled: true,
      matcher: "ProfileMatcher::YoutubeProfileMatcher",
      parameter_schema: URL_PARAMETER_SCHEMA,
      loader: { class: "Loader::YoutubeLoader", config: {} },
      processor: { class: "Processor::YoutubeProcessor", config: {} },
      normalizer: { class: "Normalizer::YoutubeNormalizer", config: {} },
      title_extractor: "TitleExtractor::YoutubeTitleExtractor"
    },
    "telegram" => {
      display_name: "Telegram",
      description: "Posts from a public Telegram channel, images included",
      input_shape: :url,
      depends_on_ai: false,
      scheduled: true,
      matcher: "ProfileMatcher::TelegramProfileMatcher",
      parameter_schema: LOOSE_URL_PARAMETER_SCHEMA,
      loader: { class: "Loader::TelegramLoader", config: {} },
      processor: { class: "Processor::TelegramProcessor", config: {} },
      normalizer: { class: "Normalizer::TelegramNormalizer", config: {} },
      title_extractor: "TitleExtractor::TelegramTitleExtractor"
    },
    "twitter" => {
      display_name: "X / Twitter",
      description: "Posts from a public X (Twitter) account",
      input_shape: :url,
      depends_on_ai: false,
      scheduled: true,
      matcher: "ProfileMatcher::TwitterProfileMatcher",
      parameter_schema: LOOSE_URL_PARAMETER_SCHEMA,
      loader: { class: "Loader::TwitterLoader", config: {} },
      processor: { class: "Processor::TwitterProcessor", config: {} },
      normalizer: { class: "Normalizer::TwitterNormalizer", config: {} },
      title_extractor: "TitleExtractor::TwitterTitleExtractor"
    },
    "bluesky" => {
      display_name: "Bluesky",
      description: "Posts from a public Bluesky account, images included",
      input_shape: :url,
      depends_on_ai: false,
      scheduled: true,
      matcher: "ProfileMatcher::BlueskyProfileMatcher",
      parameter_schema: URL_PARAMETER_SCHEMA,
      loader: { class: "Loader::BlueskyLoader", config: {} },
      processor: { class: "Processor::BlueskyProcessor", config: {} },
      normalizer: { class: "Normalizer::BlueskyNormalizer", config: {} },
      title_extractor: "TitleExtractor::BlueskyTitleExtractor"
    },
    "webhook" => {
      display_name: "Webhook",
      description: "Posts sent in from your own scripts through a secret URL",
      # Push-ingested: content arrives over HTTP, so there is
      # nothing to fetch and nothing to detect — no loader/processor, no
      # matcher, no schedule.
      input_shape: :none,
      depends_on_ai: false,
      scheduled: false,
      defaults: {
        # Prevent the form-facing writer state from rebuilding import_after.
        import_after_enabled: false,
        import_after: nil,
        images_only: false
      },
      parameter_schema: {
        "type" => "object",
        "properties" => {},
        "additionalProperties" => false
      }.freeze,
      normalizer: { class: "Normalizer::WebhookNormalizer", config: {} },
      title_extractor: nil
    }
  }.freeze

  class << self
    # @return [Array<String>] all profile keys
    def all
      PROFILES.keys
    end

    # @param key [String] the profile key
    # @return [Boolean]
    def exists?(key)
      PROFILES.key?(key)
    end

    # @param key [String] the profile key
    # @return [Hash, nil] the registry entry
    def [](key)
      PROFILES[key]
    end

    # In registration order. The AI profile registers no matcher, so it can
    # never be detected.
    # @return [Array<Class>]
    def matchers
      PROFILES.filter_map { |_key, entry| entry[:matcher].presence&.constantize }
    end

    # @param key [String] the profile key
    # @return [Boolean] true if any stage calls an LLM
    def depends_on_ai?(key)
      !!PROFILES.dig(key, :depends_on_ai)
    end

    # @param key [String] the profile key
    # @return [Boolean] true if the profile uses periodic scheduling
    def scheduled?(key)
      !!PROFILES.dig(key, :scheduled)
    end

    # @param key [String] the profile key
    # @return [Hash] attributes enforced after user-submitted attributes
    def defaults_for(key)
      PROFILES.dig(key, :defaults) || {}
    end

    # @return [Array<String>] keys of the AI-backed profiles
    def ai_profile_keys
      PROFILES.keys.select { |key| depends_on_ai?(key) }
    end

    # @param key [String] the profile key
    # @return [Hash, nil]
    def parameter_schema_for(key)
      PROFILES.dig(key, :parameter_schema)
    end

    # The params key holding the source input ("url", "prompt"), derived
    # from the profile's single required param. Unknown profiles fall back
    # to "url"; an input-less profile returns nil.
    # @param key [String] the profile key
    # @return [String, nil]
    def source_key_for(key)
      return nil if PROFILES.dig(key, :input_shape) == :none

      PROFILES.dig(key, :parameter_schema, "required")&.first || "url"
    end

    # The user-facing source value in a params hash.
    # @param key [String] the profile key
    # @param params [Hash, nil]
    # @return [String, nil]
    def source_input_for(key, params)
      (params || {})[source_key_for(key)]
    end

    # @param key [String] the profile key
    # @param stage [Symbol] :loader, :processor, or :normalizer
    # @return [Hash] the stage's config (frozen empty hash if none)
    def config_for(key, stage)
      raise ArgumentError, "Profile '#{key}' not found" unless PROFILES.key?(key)

      entry = PROFILES.fetch(key)
      raw = entry[stage]

      case raw
      when Hash then raw[:config] || {}
      else {}
      end
    end

    # @param key [String] the profile key
    # @return [Class]
    def loader_class_for(key)
      class_for(key, :loader)
    end

    # @param key [String] the profile key
    # @return [Class]
    def processor_class_for(key)
      class_for(key, :processor)
    end

    # @param key [String] the profile key
    # @return [Class]
    def normalizer_class_for(key)
      class_for(key, :normalizer)
    end

    # @param key [String] the profile key
    # @return [Class]
    def title_extractor_class_for(key)
      class_for(key, :title_extractor)
    end

    # @param key [String] the profile key
    # @return [String]
    def display_name_for(key)
      PROFILES.dig(key, :display_name) || key.to_s.titleize
    end

    private

    # @param key [String] the profile key
    # @param stage [Symbol] :loader, :processor, :normalizer, or :title_extractor
    # @return [Class]
    def class_for(key, stage)
      raise ArgumentError, "Profile '#{key}' not found" unless PROFILES.key?(key)

      entry = PROFILES.fetch(key)
      raw = entry[stage]
      class_name = raw.is_a?(Hash) ? raw[:class] : raw

      raise ArgumentError, "Profile '#{key}' has no #{stage}" if class_name.nil?

      class_name.constantize
    end
  end
end
