FactoryBot.define do
  factory :solid_queue_process, class: "SolidQueue::Process" do
    kind { "Worker" }
    sequence(:name) { |n| "test-worker-#{n}" }
    pid { Process.pid }
    hostname { "test-worker" }
    last_heartbeat_at { Time.current }
  end
end
