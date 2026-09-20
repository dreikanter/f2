class FeedProfile
  # One profile-specific feed option, read off the profile's parameter schema.
  # The declared type picks the form control, so adding an option means adding
  # a schema property and nothing else.
  class ParamOption
    BOOLEAN = "boolean"
    INTEGER = "integer"
    NUMBER = "number"

    attr_reader :name, :type, :title, :description, :default, :choices, :minimum, :maximum

    # @param name [String] the params key
    # @param schema [Hash] the property's JSON Schema fragment
    def initialize(name, schema)
      @name = name
      @type = schema["type"]
      @title = schema["title"].presence || name.humanize
      @description = schema["description"]
      @default = schema["default"]
      @choices = schema["enum"]
      @minimum = schema["minimum"]
      @maximum = schema["maximum"]
    end

    def boolean?
      type == BOOLEAN
    end

    def numeric?
      integer? || type == NUMBER
    end

    def integer?
      type == INTEGER
    end

    def choices?
      choices.present?
    end

    # @return [String] the input name the feed form submits under
    def field_name
      "feed[params][#{name}]"
    end

    # Scoped by profile: the form can render a panel per candidate, and two of
    # them may declare the same option name.
    # @param profile_key [String] the profile whose panel is rendering
    # @return [String] the input's DOM id
    def field_id(profile_key)
      "feed_params_#{profile_key}_#{name}"
    end
  end
end
