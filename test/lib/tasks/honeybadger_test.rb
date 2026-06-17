require "test_helper"
require "rake"

class HoneybadgerNotifyDeployTest < ActiveSupport::TestCase
  setup do
    F2Rails::Application.load_tasks unless Rake::Task.task_defined?("honeybadger:notify_deploy")
    @task = Rake::Task["honeybadger:notify_deploy"]
    @task.reenable
  end

  test "honeybadger:notify_deploy should track a deployment when the API key is set" do
    tracked = nil

    Honeybadger.stub(:config, { api_key: "abc123", revision: "deadbeef" }) do
      Honeybadger.stub(:track_deployment, ->(**opts) { tracked = opts; true }) do
        capture_io { @task.invoke }
      end
    end

    assert_equal "https://github.com/dreikanter/f2", tracked[:repository]
  end

  test "honeybadger:notify_deploy should skip when no API key is configured" do
    called = false

    Honeybadger.stub(:config, { api_key: nil }) do
      Honeybadger.stub(:track_deployment, ->(**) { called = true }) do
        capture_io { @task.invoke }
      end
    end

    refute called
  end
end
