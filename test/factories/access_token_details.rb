FactoryBot.define do
  factory :access_token_detail do
    association :access_token

    freefeed_user_info do
      {
        "username" => "testuser",
        "screen_name" => "Test User"
      }
    end

    managed_groups { [] }

    trait :with_userpic do
      freefeed_user_info do
        {
          "username" => "testuser",
          "screen_name" => "Test User",
          "profile_picture_url" => "https://media.freefeed.net/profilepics/testuser_75.jpg"
        }
      end
    end
  end
end
