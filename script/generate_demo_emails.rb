#!/usr/bin/env ruby
# Generate random demo emails for testing the email browser

# Random subjects and recipients
subjects = [
  "Welcome to Feeder!",
  "Your daily digest is ready",
  "Password reset requested",
  "New comment on your post",
  "Feed update: 5 new items",
  "Account verification needed",
  "Weekly summary report",
  "Important security notice",
  "Your subscription is expiring soon",
  "New follower notification",
  "Payment receipt",
  "System maintenance scheduled",
  "Feature announcement",
  "Feedback request",
  "Monthly newsletter"
]

recipients = [
  "alice@example.com",
  "bob@example.com",
  "charlie@example.com",
  "david@example.com",
  "eve@example.com",
  "frank@example.com",
  "grace@example.com"
]

# Sample paragraphs for email bodies
sample_paragraphs = [
  "Thank you for being a valued member of our community. We appreciate your continued support.",
  "This is an automated message from our system. Please do not reply to this email.",
  "We're excited to share some updates with you. Check out what's new in your dashboard.",
  "Your recent activity has been processed successfully. Here's a summary of what happened.",
  "Important: Please review the information below and take any necessary action.",
  "We noticed some activity on your account. If this wasn't you, please let us know immediately.",
  "Here's your personalized update based on your preferences and recent activity.",
  "You're receiving this email because you subscribed to our notifications.",
  "Need help? Our support team is always here to assist you with any questions.",
  "This is a friendly reminder about your upcoming subscription renewal.",
  "We've made some improvements to enhance your experience. Take a look at the latest features.",
  "Your feedback helps us improve. We'd love to hear what you think about recent changes.",
  "Stay informed with the latest updates and announcements from our team.",
  "Security is our top priority. Here are some tips to keep your account safe.",
  "Congratulations! You've reached a new milestone. Keep up the great work!"
]

# Create a temporary mailer for generating random emails
class RandomMailer < ApplicationMailer
  def random_email(subject, recipient, paragraphs)
    @paragraphs = paragraphs
    @subject = subject

    mail(
      to: recipient,
      subject: subject,
      date: Time.current - rand(0..7).days - rand(0..23).hours - rand(0..59).minutes
    ) do |format|
      format.text { render plain: paragraphs.join("\n\n") }
      format.html do
        render html: (
          "<div style='font-family: sans-serif;'>" +
          "<h2>#{subject}</h2>" +
          paragraphs.map { |p| "<p>#{p}</p>" }.join +
          "</div>"
        ).html_safe
      end
    end
  end
end

# Generate emails
count = ENV["COUNT"]&.to_i || 20

puts "Generating #{count} random demo emails..."

count.times do |i|
  subject = subjects.sample
  recipient = recipients.sample
  paragraphs = sample_paragraphs.sample(rand(2..5))

  RandomMailer.random_email(subject, recipient, paragraphs).deliver_now

  print "." if (i + 1) % 5 == 0
end

puts "\n✓ Generated #{count} demo emails!"
puts "Visit http://localhost:3000/dev/sent_emails to view them."
