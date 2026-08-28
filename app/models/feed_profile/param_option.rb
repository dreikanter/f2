class FeedProfile
  # One profile-specific feed option, read off the profile's parameter schema.
  # The declared type picks the form control, so adding an option means adding
  # a schema property and nothing else.
  class ParamOption
    # Schema types the form knows how to render. Anything else falls back to a
    # text field and reaches validation as typed.
    BOOLEAN = "boolean"

    attr_reader :name, :type, :title, :description, :default, :choices

    # @param name [String] the params key
    # @param schema [Hash] the property's JSON Schema fragment
    def initialize(name, schema)
      @name = name
      @type = schema["type"]
      @title = schema["title"].presence || name.humanize
      @description = schema["description"]
      @default = schema["default"]
      @choices = schema["enum"]
    end

    def boolean?
      type == BOOLEAN
    end

    def choices?
      choices.present?
    end

    # @return [String] the input name the feed form submits under
    def field_name
      "feed[params][#{name}]"
    end

    def field_id
      "feed_params_#{name}"
    end
  end
end
