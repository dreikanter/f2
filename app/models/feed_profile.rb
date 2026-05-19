# Feed profile registry. Each entry describes one input → posts pipeline
# (matcher + parameter shape + loader/processor/normalizer triple).
#
class FeedProfile
  STAGES = %i[loader processor normalizer].freeze

  # Shared output shape for AI-extraction profiles. All AI profiles
  # converge on this `{ items: [...] }` envelope; only the prompt and
  # the tools the loader is allowed to use differ.
  UNIVERSAL_OUTPUT_SCHEMA = {
    "type" => "object",
    "properties" => {
      "items" => {
        "type" => "array",
        "items" => {
          "type" => "object",
          "properties" => {
            "uid" => { "type" => "string" },
            "title" => { "type" => "string" },
            "body" => { "type" => "string" },
            "supplementary" => { "type" => "array", "items" => { "type" => "string" } },
            "images" => { "type" => "array", "items" => { "type" => "string" } },
            "source_url" => { "type" => "string" },
            "published_at" => { "type" => "string" }
          },
          "required" => ["uid", "body", "source_url"]
        }
      }
    },
    "required" => ["items"]
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
    "llm_website_extractor" => {
      display_name: "AI page reader",
      description: "Uses AI to extract recent posts from a webpage that doesn't expose an RSS feed",
      input_shape: :url,
      depends_on_ai: true,
      matcher: "ProfileMatcher::LlmWebsiteExtractorMatcher",
      parameter_schema: {
        "type" => "object",
        "properties" => {
          "url" => { "type" => "string", "format" => "uri" }
        },
        "required" => ["url"],
        "additionalProperties" => false
      },
      loader: {
        class: "Loader::LlmLoader",
        config: {
          model: "claude-sonnet-4-6",
          prompt_template: <<~PROMPT,
            Visit {{url}} and extract up to 10 of the most recent posts or articles.
            For each item, return a stable permalink as `uid`, a title, body text,
            an optional list of supplementary comments, an optional list of image URLs,
            the source URL, and the published date in ISO 8601.
          PROMPT
          output_schema: {
            "type" => "object",
            "properties" => {
              "items" => {
                "type" => "array",
                "items" => {
                  "type" => "object",
                  "properties" => {
                    "uid" => { "type" => "string" },
                    "title" => { "type" => "string" },
                    "body" => { "type" => "string" },
                    "supplementary" => { "type" => "array", "items" => { "type" => "string" } },
                    "images" => { "type" => "array", "items" => { "type" => "string" } },
                    "source_url" => { "type" => "string" },
                    "published_at" => { "type" => "string" }
                  },
                  "required" => ["uid", "body", "source_url"]
                }
              }
            },
            "required" => ["items"]
          },
          tools: ["web_search", "web_fetch"]
        }
      },
      processor: { class: "Processor::PassthroughProcessor", config: {} },
      normalizer: { class: "Normalizer::LlmNormalizer", config: {} },
      title_extractor: nil,
      output_schema: UNIVERSAL_OUTPUT_SCHEMA
    },
    "llm_handle_search" => {
      display_name: "Follow a handle",
      description: "Uses AI to follow posts from a social handle (X, Mastodon, …) without a structured feed",
      input_shape: :handle,
      depends_on_ai: true,
      matcher: "ProfileMatcher::LlmHandleSearchMatcher",
      parameter_schema: {
        "type" => "object",
        "properties" => {
          "handle" => { "type" => "string", "minLength" => 2, "maxLength" => 80 }
        },
        "required" => ["handle"],
        "additionalProperties" => false
      },
      loader: {
        class: "Loader::LlmLoader",
        config: {
          model: "claude-sonnet-4-6",
          prompt_template: <<~PROMPT,
            Find the most recent posts published by `{{handle}}` on any platform you can
            search. For each item, return a stable permalink as `uid`, a title, body text,
            optional supplementary comments, optional image URLs, the source URL, and the
            published date in ISO 8601. Return at most 10 items.
          PROMPT
          output_schema: nil, # filled below by reference
          tools: ["web_search"]
        }
      },
      processor: { class: "Processor::PassthroughProcessor", config: {} },
      normalizer: { class: "Normalizer::LlmNormalizer", config: {} },
      title_extractor: nil,
      output_schema: nil # filled below by reference
    },
    "llm_web_search" => {
      display_name: "Follow a web search",
      description: "Uses AI to follow results for a search query as an evergreen subscription",
      input_shape: :query,
      depends_on_ai: true,
      matcher: "ProfileMatcher::LlmWebSearchMatcher",
      parameter_schema: {
        "type" => "object",
        "properties" => {
          "query" => { "type" => "string", "minLength" => 3, "maxLength" => 200 }
        },
        "required" => ["query"],
        "additionalProperties" => false
      },
      loader: {
        class: "Loader::LlmLoader",
        config: {
          model: "claude-sonnet-4-6",
          prompt_template: <<~PROMPT,
            Search the web for `{{query}}` and return the most recent matching articles or
            posts. For each item, return a stable permalink as `uid`, a title, body text,
            optional supplementary comments, optional image URLs, the source URL, and the
            published date in ISO 8601. Return at most 10 items.
          PROMPT
          output_schema: nil,
          tools: ["web_search"]
        }
      },
      processor: { class: "Processor::PassthroughProcessor", config: {} },
      normalizer: { class: "Normalizer::LlmNormalizer", config: {} },
      title_extractor: nil,
      output_schema: nil
    }
  }.tap do |profiles|
    profiles["llm_handle_search"][:output_schema] = UNIVERSAL_OUTPUT_SCHEMA
    profiles["llm_handle_search"][:loader][:config][:output_schema] = UNIVERSAL_OUTPUT_SCHEMA
    profiles["llm_web_search"][:output_schema] = UNIVERSAL_OUTPUT_SCHEMA
    profiles["llm_web_search"][:loader][:config][:output_schema] = UNIVERSAL_OUTPUT_SCHEMA
    profiles.each_value(&:freeze)
  end.freeze

  # Returns all available profile keys
  # @return [Array<String>] list of profile keys
  def self.all
    PROFILES.keys
  end

  # Checks if a profile key exists
  # @param key [String] the profile key to check
  # @return [Boolean] true if the profile exists
  def self.exists?(key)
    PROFILES.key?(key)
  end

  # Bracket access to the full registry entry for a profile key
  # @param key [String] the profile key
  # @return [Hash, nil] the registry entry hash or nil if not found
  def self.[](key)
    PROFILES[key]
  end

  # Returns matcher classes whose input_shape accepts the given shape, in
  # registration order. Pass nil/:any to get every matcher.
  # @param input_shape [Symbol, nil] one of :url, :handle, :query, :any, nil
  # @return [Array<Class>] matcher classes
  def self.matchers_for(input_shape)
    PROFILES.filter_map do |_key, entry|
      next unless input_shape.nil? || input_shape == :any || entry[:input_shape] == input_shape || entry[:input_shape] == :any

      entry[:matcher].constantize
    end
  end

  # @param key [String] the profile key
  # @return [Boolean] true if any of the profile's stages calls an LLM
  def self.depends_on_ai?(key)
    !!PROFILES.dig(key, :depends_on_ai)
  end

  # Returns the JSON Schema describing the feed's params hash
  # @param key [String] the profile key
  # @return [Hash, nil] the parameter schema (nil if profile not found)
  def self.parameter_schema_for(key)
    PROFILES.dig(key, :parameter_schema)
  end

  # Resolves and returns a stage class for a given profile key and stage type
  # @param key [String] the profile key
  # @param stage [Symbol] the stage (:loader, :processor, :normalizer, :title_extractor)
  # @return [Class] the stage class
  def self.class_for(key, stage)
    raise ArgumentError, "Profile '#{key}' not found" unless PROFILES.key?(key)

    entry = PROFILES.fetch(key)
    raw = entry[stage]
    class_name = raw.is_a?(Hash) ? raw[:class] : raw

    raise ArgumentError, "Profile '#{key}' has no #{stage}" if class_name.nil?

    class_name.constantize
  end

  # @param key [String] the profile key
  # @param stage [Symbol] the stage (:loader, :processor, :normalizer)
  # @return [Hash] the stage's config hash (frozen empty hash if none)
  def self.config_for(key, stage)
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
  def self.loader_class_for(key)
    class_for(key, :loader)
  end

  # Resolves and returns the processor class for a given profile key
  # @param key [String] the profile key
  # @return [Class] the processor class
  def self.processor_class_for(key)
    class_for(key, :processor)
  end

  # Resolves and returns the normalizer class for a given profile key
  # @param key [String] the profile key
  # @return [Class] the normalizer class
  def self.normalizer_class_for(key)
    class_for(key, :normalizer)
  end

  # Resolves and returns the title extractor class for a given profile key
  # @param key [String] the profile key
  # @return [Class] the title extractor class
  def self.title_extractor_class_for(key)
    class_for(key, :title_extractor)
  end

  # Returns a human-readable display name for a profile key
  # @param key [String] the profile key
  # @return [String] the display name
  def self.display_name_for(key)
    PROFILES.dig(key, :display_name) || key.to_s.titleize
  end
end
