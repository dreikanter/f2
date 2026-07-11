namespace :honeybadger do
  desc "Notify Honeybadger that a new revision has been deployed"
  task notify_deploy: :environment do
    if Honeybadger.config[:api_key].blank?
      puts "Honeybadger API key not configured; skipping deploy notification."
    elsif Honeybadger.track_deployment(repository: F2Rails::GITHUB_REPO_URL)
      puts "Honeybadger notified of deploy (#{Honeybadger.config[:revision] || 'unknown revision'})."
    else
      warn "Honeybadger deploy notification failed."
    end
  end
end
