class CandidateOptionComponent < ViewComponent::Base
  # Renders one working detection candidate as a radio option in the "How should
  # we fetch posts?" chooser: its name, description, post-count verdict, and a
  # "Suggested" flag on the preselected default. Only candidates that can fetch
  # the source reach the chooser (spec §7), so every option is selectable.
  def initialize(candidate:, input:, selected:)
    @candidate = candidate
    @input = input
    @selected = selected
  end

  private

  attr_reader :candidate, :input

  def profile_key
    candidate.profile_key
  end

  def display_name
    helpers.candidate_summary(profile_key, input)
  end

  def description
    FeedProfile[profile_key]&.dig(:description)
  end

  def selected?
    profile_key == @selected
  end

  def row_classes
    if selected?
      "border-ring bg-brand-subtle cursor-pointer"
    else
      "border-border bg-surface cursor-pointer hover:border-ring"
    end
  end

  # Every shown candidate passed its self-test; badge the post count and note an
  # empty-but-valid source.
  def badge_text
    count = candidate.posts_found
    count.zero? ? "Tested" : "Tested · #{count} #{'post'.pluralize(count)}"
  end

  def note
    "No posts yet. We'll pick up new ones as they're published." if candidate.posts_found.zero?
  end
end
