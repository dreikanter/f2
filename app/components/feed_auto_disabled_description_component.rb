# Appends the failure count to an auto-disable description, e.g.
# "My Feed was turned off after repeated errors (10 failures in a row)".
# The threshold is a constant, but spelling it out tells the user how much
# patience the system had before giving up.
class FeedAutoDisabledDescriptionComponent < EventDescriptionComponent
  def call
    suffix = error_count_tag
    suffix ? safe_join([super, suffix], " ") : super
  end

  private

  def error_count_tag
    count = event.metadata["error_count"].to_i
    return if count.zero?

    helpers.tag.span("(#{helpers.pluralize(count, "failure")} in a row)",
                     class: "text-slate-400", data: { key: "events.error_count" })
  end
end
