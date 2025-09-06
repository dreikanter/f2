# Preview all emails at http://localhost:3000/rails/mailers/profile_mailer
class ProfileMailerPreview < ActionMailer::Preview
  # Preview this email at http://localhost:3000/rails/mailers/profile_mailer/email_change_confirmation
  def email_change_confirmation
    ProfileMailer.email_change_confirmation
  end
end
