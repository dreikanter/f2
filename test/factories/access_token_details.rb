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

    trait :with_userpic do
      data do
        {
          user_info: {
            username: "testuser",
            screen_name: "Test User",
            profile_picture_url: "https://media.freefeed.net/profilepics/testuser_75.jpg"
          },
          managed_groups: []
        }
      end
    end
  end
end
