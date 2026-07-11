module SystemStatusHelper
  # GitHub resolves short hashes in commit URLs, so a missing full revision
  # doesn't block linking.
  def revision_commit_link(revision_short, revision)
    link_to tag.code(revision_short, title: revision),
            "#{F2Rails::GITHUB_REPO_URL}/commit/#{revision.presence || revision_short}",
            target: "_blank", rel: "noopener",
            class: "text-brand underline underline-offset-4 transition hover:text-brand-hover"
  end
end
