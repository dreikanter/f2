# Profile-specific feed options, rendered from the profile's parameter schema.
# A new option is a schema property; no view change goes with it.
class FeedProfileOptionsComponent < ViewComponent::Base
  def initialize(feed:)
    @feed = feed
  end

  def render?
    options.any?
  end

  def options
    @options ||= FeedProfile.options_for(feed.feed_profile_key)
  end

  # @param option [FeedProfile::ParamOption] the option to read
  # @return [Object] the stored value, or the schema default when unset
  def value_for(option)
    stored = (feed.params || {})[option.name]
    stored.nil? ? option.default : stored
  end

  def checked?(option)
    ActiveModel::Type::Boolean.new.cast(value_for(option)) || false
  end

  # @param option [FeedProfile::ParamOption] the option to render
  # @return [Array<Array>] label/value pairs for a select
  def choices_for(option)
    option.choices.map { |choice| [choice.to_s.humanize, choice] }
  end

  private

  attr_reader :feed
end
