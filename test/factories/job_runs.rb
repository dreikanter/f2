FactoryBot.define do
  factory :job_run do
    job_class { "PurgeExpiredEventsJob" }
    status { "queued" }
  end
end
