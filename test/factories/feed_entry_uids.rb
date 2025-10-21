FactoryBot.define do
  factory :feed_entry_uid do
    feed { association(:feed) }
    uid { SecureRandom.uuid }
    imported_at { 2.hours.ago }
  end
end
