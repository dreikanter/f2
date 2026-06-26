class CandidateOptionComponent < ViewComponent::Base
  # Renders one detection candidate as a radio option in the "How should we fetch
  # posts?" chooser: its name, description, self-test verdict badge, and note.
  def initialize(candidate:, input:, selected:, single: false)
    @candidate = candidate
    @input = input
    @selected = selected
    @single = single
  end

  def before_render
    assign_verdict
  end

  private

  attr_reader :candidate, :input, :badge_text, :badge_color, :note

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

  def disabled?
    @single || candidate.failed?
  end

  # Only badge a usable default: a disabled (failed) candidate is never worth
  # flagging even when it's the one preselected.
  def suggested?
    selected? && !disabled?
  end

  def row_classes
    if disabled? && !@single
      "border-slate-200 bg-slate-50 opacity-70 cursor-not-allowed"
    elsif @single
      "border-sky-300 bg-sky-50 cursor-default"
    else
      "border-slate-200 bg-white cursor-pointer hover:border-sky-400"
    end
  end

  # Resolve the self-test verdict to its badge and note once. A candidate with
  # no verdict leaves badge_text nil, so the template renders no badge.
  def assign_verdict
    if candidate.passed?
      count = candidate.posts_found
      @badge_text = count.zero? ? "Tested" : "Tested · #{count} #{'post'.pluralize(count)}"
      @badge_color = :green
      @note = "No posts yet. We'll pick up new ones as they're published." if count.zero?
    elsif candidate.unreachable?
      @badge_text = "Couldn't reach"
      @badge_color = :yellow
      @note = "We couldn't reach the source just now. Pick this only if you think it's temporary."
    elsif candidate.failed?
      @badge_text = "Won't work"
      @badge_color = :red
      @note = "We tried, but couldn't read any posts from this source."
    elsif candidate.not_tested?
      @badge_text = "Not tested"
      @badge_color = :gray
    end
  end
end
