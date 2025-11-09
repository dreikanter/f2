FactoryBot.define do
  factory :access_token_detail do
    association :access_token

    data do
      {
        user_info: {
          username: "testuser",
          screen_name: "Test User"
        },
        managed_groups: []
      }
    end
  end
end
