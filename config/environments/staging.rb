require_relative "production"

Rails.application.configure do
  hosts = ENV.fetch("HOSTS").split(",").map(&:strip)
  config.hosts = hosts
end
