FactoryBot.define do
  factory :operation_run do
    association :subject, factory: :access_token
    kind { :validation }
    status { :running }
    started_at { Time.current }
    deadline_at { 15.minutes.from_now }
  end
end
