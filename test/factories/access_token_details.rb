FactoryBot.define do
  factory :access_token_detail do
    association :access_token
    data do
      {
        user_info: { username: "testuser", screen_name: "Test User" },
        managed_groups: [],
        cached_at: Time.current.iso8601
      }
    end
    expires_at { AccessTokenDetail::TTL.from_now }
  end
end
