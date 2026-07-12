module SystemStatusHelper
  # Badge colors signal how careful to be: red for production, orange for
  # staging, green for development, gray for anything else.
  ENVIRONMENT_BADGE_COLORS = {
    "production" => :danger,
    "staging" => :warning,
    "development" => :success
  }.freeze

  def environment_badge(env = Rails.env)
    render BadgeComponent.new(text: env, color: ENVIRONMENT_BADGE_COLORS.fetch(env.to_s, :neutral))
  end

  # GitHub resolves short hashes in commit URLs, so a missing full revision
  # doesn't block linking.
  def revision_commit_link(revision_short, revision)
    link_to tag.code(revision_short, title: revision),
            "#{F2Rails::GITHUB_REPO_URL}/commit/#{revision.presence || revision_short}",
            target: "_blank", rel: "noopener",
            class: "text-brand underline underline-offset-4 transition hover:text-brand-hover"
  end
end
