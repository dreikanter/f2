FactoryBot.define do
  factory :session do
    user
    ip_address { "127.0.0.1" }
    user_agent { "Test Browser" }
    last_seen_at { Time.current }
  end
end
