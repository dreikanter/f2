# Profile-specific feed options, rendered from the profile's parameter schema.
# A new option is a schema property; no view change goes with it.
#
# While the candidate chooser is live the form can submit any of several
# profiles, so every candidate's panel is rendered and the Stimulus controller
# keeps only the selected one enabled.
class FeedProfileOptionsComponent < ViewComponent::Base
  # @param feed [Feed] the feed being created or edited
  # @param profile_keys [Array<String>] profiles the form can submit
  def initialize(feed:, profile_keys: [])
    @feed = feed
    @profile_keys = profile_keys.presence || [feed.feed_profile_key].compact
  end

  def render?
    groups.any?
  end

  # @return [Array<Array(String, Array<FeedProfile::ParamOption>)>] the profiles
  #   that declare options, with theirs
  def groups
    @groups ||= @profile_keys.uniq.filter_map do |profile_key|
      options = FeedProfile.options_for(profile_key)
      [profile_key, options] if options.any?
    end
  end

  def selected?(profile_key)
    profile_key == feed.feed_profile_key
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
