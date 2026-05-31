require "test_helper"
require "erb"

class ScheduledJobsTest < ActiveSupport::TestCase
  test "crontab should enqueue the feed scheduler every five minutes" do
    assert_includes crontab, '*/5 * * * * bin/rails runner "FeedSchedulerJob.perform_later"'
  end

  test "crontab should enqueue expired event purge daily at midnight" do
    assert_includes crontab, '0 0 * * * bin/rails runner "PurgeExpiredEventsJob.perform_later"'
  end

  test "queue configuration should not run the Solid Queue recurring scheduler" do
    config = YAML.safe_load(ERB.new(Rails.root.join("config/queue.yml").read).result, aliases: true)

    assert_not config.fetch("default").key?("schedulers")
  end

  private

  def crontab
    @crontab ||= Rails.root.join("config/crontab").read
  end
end
