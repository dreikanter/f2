FactoryBot.define do
  factory :llm_chat do
    association :user
    requested_provider { "openai" }
    requested_model { "gpt-5-nano" }
    profile_key { "llm" }
    purpose { :scheduled_run }
    started_at { Time.current }
    deadline_at { 5.minutes.from_now }
    model do
      info = RubyLLM.models.find(requested_model, provider: requested_provider)
      RubyLLM::ActiveRecord::Model.find_or_create_by!(provider: info.provider, model_id: info.id) do |record|
        record.name = info.name
      end
    end
  end
end
