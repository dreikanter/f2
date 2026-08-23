namespace :admin do
  desc "Create the initial admin account and print a link to set its password (EMAIL=you@example.com)"
  task create: :environment do
    email = ENV["EMAIL"].to_s.strip
    abort "Usage: bin/rails admin:create EMAIL=you@example.com" if email.blank?

    user = User.find_by(email_address: email)

    if user
      puts "#{user.email_address} already exists, leaving it as it is."
    else
      # A throwaway password nobody has to keep: the reset link below is how the
      # account gets a real one, so no interim credential is typed or shared.
      user = User.create!(
        email_address: email,
        name: ENV.fetch("NAME", "Admin"),
        state: :active,
        available_invites: ENV.fetch("INVITES", "10").to_i,
        password: SecureRandom.alphanumeric(32)
      )
      puts "Created #{user.email_address}."
    end

    puts "Granted admin." if user.permissions.find_or_create_by!(name: Permission::ADMIN).previously_new_record?

    warn "Account is #{user.state}, so signing in will refuse it." unless user.active?
    warn "Email is deactivated (#{user.email_deactivation_reason}), so Feeder won't mail this address." if user.email_deactivated?

    url = Rails.application.routes.url_helpers.edit_password_url(
      user.generate_token_for(:password_reset),
      host: Rails.application.config.action_mailer.default_url_options.fetch(:host),
      protocol: Rails.application.config.force_ssl ? "https" : "http"
    )

    puts "Set a password within #{User::PASSWORD_RESET_TTL.inspect}: #{url}"
  end
end
