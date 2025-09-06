# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Create a test user for development
if Rails.env.development?
  user = User.find_or_create_by!(email_address: "test@example.com") do |user|
    user.password = "password"
    user.password_confirmation = "password"
  end
  puts "✅ Development user created: test@example.com / password"

  # Add admin permission to the first user
  user.permissions.find_or_create_by!(name: "admin")
  puts "✅ Admin permission granted to first user"
end
