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
            # The model never mints the uid — the processor derives it from
            # source_url (spec §3). `uid` stays an accepted-but-optional property
            # only so a stray field from a non-strict provider doesn't fail the
            # schema; it's ignored downstream.
            "uid" => { "type" => "string" },
            "title" => { "type" => "string" },
            "body" => { "type" => "string" },
            "supplementary" => { "type" => "array", "items" => { "type" => "string" } },
            "images" => { "type" => "array", "items" => { "type" => "string" } },
            # An explicit null signals the digest/standing-query regime; a real
            # permalink signals feed-style (spec §3). The key is always required —
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

  PROFILES = {
    "rss" => {
      display_name: "RSS Feed",
      description: "Posts from a site's RSS or Atom feed",
      input_shape: :url,
      depends_on_ai: false,
      matcher: "ProfileMatcher::RssProfileMatcher",
      parameter_schema: {
        "type" => "object",
        "properties" => {
          "url" => { "type" => "string", "format" => "uri" }
        },
        "required" => ["url"],
        "additionalProperties" => false
      },
      loader: { class: "Loader::HttpLoader", config: {} },
      processor: { class: "Processor::RssProcessor", config: {} },
      normalizer: { class: "Normalizer::RssNormalizer", config: {} },
      title_extractor: "TitleExtractor::RssTitleExtractor",
      output_schema: nil
    },
    "json_feed" => {
      display_name: "JSON Feed",
      description: "Posts from a site's JSON feed (jsonfeed.org)",
      input_shape: :url,
      depends_on_ai: false,
      matcher: "ProfileMatcher::JsonFeedProfileMatcher",
      parameter_schema: {
        "type" => "object",
        "properties" => {
          "url" => { "type" => "string", "format" => "uri" }
        },
        "required" => ["url"],
        "additionalProperties" => false
      },
      loader: { class: "Loader::HttpLoader", config: {} },
      processor: { class: "Processor::JsonFeedProcessor", config: {} },
      normalizer: { class: "Normalizer::JsonFeedNormalizer", config: {} },
      title_extractor: "TitleExtractor::JsonFeedTitleExtractor",
      output_schema: nil
    },
    "reddit" => {
      display_name: "Reddit",
      description: "Posts from a subreddit or Reddit user page via RSS",
      input_shape: :url,
      depends_on_ai: false,
      matcher: "ProfileMatcher::RedditProfileMatcher",
      parameter_schema: {
        "type" => "object",
        "properties" => {
          "url" => { "type" => "string", "minLength" => 2 }
        },
        "required" => ["url"],
        "additionalProperties" => false
      },
      loader: { class: "Loader::RedditLoader", config: {} },
      processor: { class: "Processor::RssProcessor", config: {} },
      normalizer: { class: "Normalizer::RedditNormalizer", config: {} },
      title_extractor: "TitleExtractor::RssTitleExtractor",
      output_schema: nil
    },
    "xkcd" => {
      display_name: "XKCD",
      description: "Posts from xkcd.com with the alt text included",
      input_shape: :url,
      depends_on_ai: false,
      matcher: "ProfileMatcher::XkcdProfileMatcher",
      parameter_schema: {
        "type" => "object",
        "properties" => {
          "url" => { "type" => "string", "format" => "uri" }
        },
        "required" => ["url"],
        "additionalProperties" => false
      },
      loader: { class: "Loader::HttpLoader", config: {} },
      processor: { class: "Processor::RssProcessor", config: {} },
      normalizer: { class: "Normalizer::XkcdNormalizer", config: {} },
      title_extractor: "TitleExtractor::RssTitleExtractor",
      output_schema: nil
    },
    "buni" => {
      display_name: "Buni Comic",
      description: "Wordless Buni comic strips from bunicomic.com",
      input_shape: :url,
      depends_on_ai: false,
      matcher: "ProfileMatcher::BuniProfileMatcher",
      parameter_schema: {
        "type" => "object",
        "properties" => {
          "url" => { "type" => "string", "format" => "uri" }
        },
        "required" => ["url"],
        "additionalProperties" => false
      },
      loader: { class: "Loader::HttpLoader", config: {} },
      processor: { class: "Processor::RssProcessor", config: {} },
      normalizer: { class: "Normalizer::BuniNormalizer", config: {} },
      title_extractor: "TitleExtractor::RssTitleExtractor",
      output_schema: nil
    },
    "elementy" => {
      display_name: "Elementy",
      description: "Science news from elementy.ru with cover images",
      input_shape: :url,
      depends_on_ai: false,
      matcher: "ProfileMatcher::ElementyProfileMatcher",
      parameter_schema: {
        "type" => "object",
        "properties" => {
          "url" => { "type" => "string", "format" => "uri" }
        },
        "required" => ["url"],
        "additionalProperties" => false
      },
      loader: { class: "Loader::HttpLoader", config: {} },
      processor: { class: "Processor::RssProcessor", config: {} },
      normalizer: { class: "Normalizer::ElementyNormalizer", config: {} },
      title_extractor: "TitleExtractor::RssTitleExtractor",
      output_schema: nil
    },
    "melodymae" => {
      display_name: "Melody Mae",
      description: "Posts from Melody Mae's plus-size fashion blog at melodymae.co.uk",
      input_shape: :url,
      depends_on_ai: false,
      matcher: "ProfileMatcher::MelodymaeProfileMatcher",
      parameter_schema: {
        "type" => "object",
        "properties" => {
          "url" => { "type" => "string", "format" => "uri" }
        },
        "required" => ["url"],
        "additionalProperties" => false
      },
      loader: { class: "Loader::HttpLoader", config: {} },
      processor: { class: "Processor::RssProcessor", config: {} },
      normalizer: { class: "Normalizer::MelodymaeNormalizer", config: {} },
      title_extractor: "TitleExtractor::RssTitleExtractor",
      output_schema: nil
    },
    "nextbigfuture" => {
      display_name: "Next Big Future",
      description: "Technology news from nextbigfuture.com with cover images",
      input_shape: :url,
      depends_on_ai: false,
      matcher: "ProfileMatcher::NextbigfutureProfileMatcher",
      parameter_schema: {
        "type" => "object",
        "properties" => {
          "url" => { "type" => "string", "format" => "uri" }
        },
        "required" => ["url"],
        "additionalProperties" => false
      },
      loader: { class: "Loader::HttpLoader", config: {} },
      processor: { class: "Processor::RssProcessor", config: {} },
      normalizer: { class: "Normalizer::NextbigfutureNormalizer", config: {} },
      title_extractor: "TitleExtractor::RssTitleExtractor",
      output_schema: nil
    },
    "monkeyuser" => {
      display_name: "MonkeyUser",
      description: "MonkeyUser comics for developers",
      input_shape: :url,
      depends_on_ai: false,
      matcher: "ProfileMatcher::MonkeyuserProfileMatcher",
      parameter_schema: {
        "type" => "object",
        "properties" => {
          "url" => { "type" => "string", "format" => "uri" }
        },
        "required" => ["url"],
        "additionalProperties" => false
      },
      loader: { class: "Loader::HttpLoader", config: {} },
      processor: { class: "Processor::RssProcessor", config: {} },
      normalizer: { class: "Normalizer::MonkeyuserNormalizer", config: {} },
      title_extractor: "TitleExtractor::RssTitleExtractor",
      output_schema: nil
    },
    "lobsters" => {
      display_name: "Lobsters",
      description: "Stories from lobste.rs with a link to the discussion",
      input_shape: :url,
      depends_on_ai: false,
      matcher: "ProfileMatcher::LobstersProfileMatcher",
      parameter_schema: {
        "type" => "object",
        "properties" => {
          "url" => { "type" => "string", "format" => "uri" }
        },
        "required" => ["url"],
        "additionalProperties" => false
      },
      loader: { class: "Loader::HttpLoader", config: {} },
      processor: { class: "Processor::RssProcessor", config: {} },
      normalizer: { class: "Normalizer::LobstersNormalizer", config: {} },
      title_extractor: "TitleExtractor::RssTitleExtractor",
      output_schema: nil
    },
    "litterbox" => {
      display_name: "Litterbox Comics",
      description: "Family life comics from Litterbox Comics, bonus panels included",
      input_shape: :url,
      depends_on_ai: false,
      matcher: "ProfileMatcher::LitterboxProfileMatcher",
      parameter_schema: {
        "type" => "object",
        "properties" => {
          "url" => { "type" => "string", "format" => "uri" }
        },
        "required" => ["url"],
        "additionalProperties" => false
      },
      loader: { class: "Loader::HttpLoader", config: {} },
      processor: { class: "Processor::RssProcessor", config: {} },
      normalizer: { class: "Normalizer::LitterboxNormalizer", config: {} },
      title_extractor: "TitleExtractor::RssTitleExtractor",
      output_schema: nil
    },
    "oglaf" => {
      display_name: "Oglaf",
      description: "Comic strips from oglaf.com, multi-page stories included",
      input_shape: :url,
      depends_on_ai: false,
      matcher: "ProfileMatcher::OglafProfileMatcher",
      parameter_schema: {
        "type" => "object",
        "properties" => {
          "url" => { "type" => "string", "format" => "uri" }
        },
        "required" => ["url"],
        "additionalProperties" => false
      },
      loader: { class: "Loader::HttpLoader", config: {} },
      processor: { class: "Processor::RssProcessor", config: {} },
      normalizer: { class: "Normalizer::OglafNormalizer", config: {} },
      title_extractor: "TitleExtractor::RssTitleExtractor",
      output_schema: nil
    },
    "pluralistic" => {
      display_name: "Pluralistic",
      description: "Cory Doctorow's Pluralistic linkblog with cover images",
      input_shape: :url,
      depends_on_ai: false,
      matcher: "ProfileMatcher::PluralisticProfileMatcher",
      parameter_schema: {
        "type" => "object",
        "properties" => {
          "url" => { "type" => "string", "format" => "uri" }
        },
        "required" => ["url"],
        "additionalProperties" => false
      },
      loader: { class: "Loader::HttpLoader", config: {} },
      processor: { class: "Processor::RssProcessor", config: {} },
      normalizer: { class: "Normalizer::PluralisticNormalizer", config: {} },
      title_extractor: "TitleExtractor::RssTitleExtractor",
      output_schema: nil
    },
    "smbc" => {
      display_name: "SMBC Comics",
      description: "Saturday Morning Breakfast Cereal comics with the hovertext and hidden panel",
      input_shape: :url,
      depends_on_ai: false,
      matcher: "ProfileMatcher::SmbcProfileMatcher",
      parameter_schema: {
        "type" => "object",
        "properties" => {
          "url" => { "type" => "string", "format" => "uri" }
        },
        "required" => ["url"],
        "additionalProperties" => false
      },
      loader: { class: "Loader::HttpLoader", config: {} },
      processor: { class: "Processor::RssProcessor", config: {} },
      normalizer: { class: "Normalizer::SmbcNormalizer", config: {} },
      title_extractor: "TitleExtractor::RssTitleExtractor",
      output_schema: nil
    },
    "aerostat" => {
      display_name: "Aerostat",
      description: "Boris Grebenshchikov's Aerostat radio show episodes",
      input_shape: :url,
      depends_on_ai: false,
      matcher: "ProfileMatcher::AerostatProfileMatcher",
      parameter_schema: {
        "type" => "object",
        "properties" => {
          "url" => { "type" => "string", "format" => "uri" }
        },
        "required" => ["url"],
        "additionalProperties" => false
      },
      loader: { class: "Loader::HttpLoader", config: {} },
      processor: { class: "Processor::AerostatProcessor", config: {} },
      normalizer: { class: "Normalizer::AerostatNormalizer", config: {} },
      title_extractor: "TitleExtractor::RssTitleExtractor",
      output_schema: nil
    },
    "theycantalk" => {
      display_name: "They Can Talk",
      description: "They Can Talk comics about what animals might say",
      input_shape: :url,
      depends_on_ai: false,
      matcher: "ProfileMatcher::TheycantalkProfileMatcher",
      parameter_schema: {
        "type" => "object",
        "properties" => {
          "url" => { "type" => "string", "format" => "uri" }
        },
        "required" => ["url"],
        "additionalProperties" => false
      },
      loader: { class: "Loader::HttpLoader", config: {} },
      processor: { class: "Processor::RssProcessor", config: {} },
      normalizer: { class: "Normalizer::TheycantalkNormalizer", config: {} },
      title_extractor: "TitleExtractor::RssTitleExtractor",
      output_schema: nil
    },
    "tomorrows" => {
      display_name: "365 Tomorrows",
      description: "Daily flash science fiction from 365tomorrows.com",
      input_shape: :url,
      depends_on_ai: false,
      matcher: "ProfileMatcher::TomorrowsProfileMatcher",
      parameter_schema: {
        "type" => "object",
        "properties" => {
          "url" => { "type" => "string", "format" => "uri" }
        },
        "required" => ["url"],
        "additionalProperties" => false
      },
      loader: { class: "Loader::HttpLoader", config: {} },
      processor: { class: "Processor::RssProcessor", config: {} },
      normalizer: { class: "Normalizer::TomorrowsNormalizer", config: {} },
      title_extractor: "TitleExtractor::RssTitleExtractor",
      output_schema: nil
    },
    "llm" => {
      display_name: "AI",
      description: "Uses AI to follow and transform web content per a free-form prompt",
      # Accepts anything (a link, several links, or a description); the prompt
      # is the source. The params key is `prompt`, not derived from input_shape.
      # Registers NO matcher: the AI profile is structurally excluded from
      # detection (spec §7) — Mode B selects it directly, detection never can.
      input_shape: :any,
      depends_on_ai: true,
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
          # The user message: the task, output contract, and safeguards live in
          # the system prompt (Loader::LlmPrompts). The user's own prompt is a
          # legitimate instruction — it says what to follow and how to transform
          # it (spec §2/§8) — so it travels as the user message, distinct from
          # the untrusted web content the model later fetches. Web access is
          # provided per-provider by the adapter.
          prompt_template: <<~PROMPT,
            Feed request — what to follow and how to present it:

            {{input}}
          PROMPT
          output_schema: UNIVERSAL_OUTPUT_SCHEMA
        }
      },
      processor: { class: "Processor::PassthroughProcessor", config: {} },
      normalizer: { class: "Normalizer::LlmNormalizer", config: {} },
      title_extractor: nil,
      output_schema: UNIVERSAL_OUTPUT_SCHEMA
    },
    "youtube" => {
      display_name: "YouTube",
      description: "Videos from a YouTube channel",
      input_shape: :url,
      depends_on_ai: false,
      matcher: "ProfileMatcher::YoutubeProfileMatcher",
      parameter_schema: {
        "type" => "object",
        "properties" => {
          "url" => { "type" => "string", "format" => "uri" }
        },
        "required" => ["url"],
        "additionalProperties" => false
      },
      loader: { class: "Loader::YoutubeLoader", config: {} },
      processor: { class: "Processor::YoutubeProcessor", config: {} },
      normalizer: { class: "Normalizer::YoutubeNormalizer", config: {} },
      title_extractor: "TitleExtractor::YoutubeTitleExtractor",
      output_schema: nil
    },
    "telegram" => {
      display_name: "Telegram",
      description: "Posts from a public Telegram channel, images included",
      input_shape: :url,
      depends_on_ai: false,
      matcher: "ProfileMatcher::TelegramProfileMatcher",
      parameter_schema: {
        "type" => "object",
        "properties" => {
          "url" => { "type" => "string", "minLength" => 2 }
        },
        "required" => ["url"],
        "additionalProperties" => false
      },
      loader: { class: "Loader::TelegramLoader", config: {} },
      processor: { class: "Processor::TelegramProcessor", config: {} },
      normalizer: { class: "Normalizer::TelegramNormalizer", config: {} },
      title_extractor: "TitleExtractor::TelegramTitleExtractor",
      output_schema: nil
    },
    "twitter" => {
      display_name: "X / Twitter",
      description: "Posts from a public X (Twitter) account",
      input_shape: :url,
      depends_on_ai: false,
      matcher: "ProfileMatcher::TwitterProfileMatcher",
      parameter_schema: {
        "type" => "object",
        "properties" => {
          "url" => { "type" => "string", "minLength" => 2 }
        },
        "required" => ["url"],
        "additionalProperties" => false
      },
      loader: { class: "Loader::TwitterLoader", config: {} },
      processor: { class: "Processor::TwitterProcessor", config: {} },
      normalizer: { class: "Normalizer::TwitterNormalizer", config: {} },
      title_extractor: "TitleExtractor::TwitterTitleExtractor",
      output_schema: nil
    }
  }.freeze

  class << self
    # Returns all available profile keys
    # @return [Array<String>] list of profile keys
    def all
      PROFILES.keys
    end

    # Checks if a profile key exists
    # @param key [String] the profile key to check
    # @return [Boolean] true if the profile exists
    def exists?(key)
      PROFILES.key?(key)
    end

    # Bracket access to the full registry entry for a profile key
    # @param key [String] the profile key
    # @return [Hash, nil] the registry entry hash or nil if not found
    def [](key)
      PROFILES[key]
    end

    # Returns matcher classes whose input_shape accepts the given shape, in
    # registration order. Pass nil/:any to get every matcher.
    # @param input_shape [Symbol, nil] one of :url, :query, :any, nil
    # @return [Array<Class>] matcher classes
    def matchers_for(input_shape)
      PROFILES.filter_map do |_key, entry|
        next if entry[:matcher].blank?
        next unless input_shape.nil? || input_shape == :any || entry[:input_shape] == input_shape || entry[:input_shape] == :any

        entry[:matcher].constantize
      end
    end

    # @param key [String] the profile key
    # @return [Boolean] true if any of the profile's stages calls an LLM
    def depends_on_ai?(key)
      !!PROFILES.dig(key, :depends_on_ai)
    end

    # @return [Array<String>] keys of the AI-backed profiles
    def ai_profile_keys
      PROFILES.keys.select { |key| depends_on_ai?(key) }
    end

    # Returns the JSON Schema describing the feed's params hash
    # @param key [String] the profile key
    # @return [Hash, nil] the parameter schema (nil if profile not found)
    def parameter_schema_for(key)
      PROFILES.dig(key, :parameter_schema)
    end

    # The params key holding the feed's source input (e.g. "url", "prompt").
    # Derived from the profile's single required param, so the storage key is
    # independent of input_shape (which an `:any` profile can't double as).
    # Unknown profiles fall back to "url".
    # @param key [String] the profile key
    # @return [String] the source params key
    def source_key_for(key)
      PROFILES.dig(key, :parameter_schema, "required")&.first || "url"
    end

    # The user-facing source value stored in a params hash, read by the
    # profile's source key.
    # @param key [String] the profile key
    # @param params [Hash, nil] a feed/preview params hash
    # @return [String, nil] the source value
    def source_input_for(key, params)
      (params || {})[source_key_for(key)]
    end

    # @param key [String] the profile key
    # @param stage [Symbol] the stage (:loader, :processor, :normalizer)
    # @return [Hash] the stage's config hash (frozen empty hash if none)
    def config_for(key, stage)
      raise ArgumentError, "Profile '#{key}' not found" unless PROFILES.key?(key)

      entry = PROFILES.fetch(key)
      raw = entry[stage]

      case raw
      when Hash then raw[:config] || {}
      else {}
      end
    end

    # Resolves and returns the loader class for a given profile key
    # @param key [String] the profile key
    # @return [Class] the loader class
    def loader_class_for(key)
      class_for(key, :loader)
    end

    # Resolves and returns the processor class for a given profile key
    # @param key [String] the profile key
    # @return [Class] the processor class
    def processor_class_for(key)
      class_for(key, :processor)
    end

    # Resolves and returns the normalizer class for a given profile key
    # @param key [String] the profile key
    # @return [Class] the normalizer class
    def normalizer_class_for(key)
      class_for(key, :normalizer)
    end

    # Resolves and returns the title extractor class for a given profile key
    # @param key [String] the profile key
    # @return [Class] the title extractor class
    def title_extractor_class_for(key)
      class_for(key, :title_extractor)
    end

    # Returns a human-readable display name for a profile key
    # @param key [String] the profile key
    # @return [String] the display name
    def display_name_for(key)
      PROFILES.dig(key, :display_name) || key.to_s.titleize
    end

    private

    # Resolves a stage class for a given profile key and stage type.
    # @param key [String] the profile key
    # @param stage [Symbol] the stage (:loader, :processor, :normalizer, :title_extractor)
    # @return [Class] the stage class
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
