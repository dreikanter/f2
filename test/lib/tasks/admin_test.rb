require "test_helper"
require "rake"

class AdminCreateTaskTest < ActiveSupport::TestCase
  setup do
    Feeder::Application.load_tasks unless Rake::Task.task_defined?("admin:create")
    @task = Rake::Task["admin:create"]
    @task.reenable
  end

  teardown do
    ENV.delete("EMAIL")
    ENV.delete("NAME")
    ENV.delete("INVITES")
  end

  test "admin:create should create a confirmed admin account" do
    ENV["EMAIL"] = "owner@example.com"

    run_task

    user = User.find_by(email_address: "owner@example.com")
    assert user.active?
    assert user.admin?
    assert_equal 10, user.available_invites
  end

  test "admin:create should print a password reset link instead of a password" do
    ENV["EMAIL"] = "owner@example.com"

    output = run_task
    token = output[%r{/passwords/([^/]+)/edit}, 1]

    assert_equal User.find_by(email_address: "owner@example.com"), User.find_by_password_reset_token!(token)
  end

  test "admin:create should leave an existing account untouched" do
    user = create(:user, email_address: "owner@example.com", name: "Original")
    ENV["EMAIL"] = "owner@example.com"
    ENV["NAME"] = "Replacement"

    run_task

    user.reload
    assert_equal "Original", user.name
    assert_equal 1, User.where(email_address: "owner@example.com").count
  end

  test "admin:create should keep an existing password working" do
    user = create(:user, email_address: "owner@example.com")
    ENV["EMAIL"] = "owner@example.com"

    run_task

    assert User.authenticate_by(email_address: user.email_address, password: "password123")
  end

  test "admin:create should grant admin to an existing account that lacks it" do
    user = create(:user, email_address: "owner@example.com")
    ENV["EMAIL"] = "owner@example.com"

    run_task

    assert user.reload.admin?
    assert_equal 1, user.permissions.where(name: Permission::ADMIN).count
  end

  test "admin:create should normalize the email address" do
    ENV["EMAIL"] = "  Owner@Example.com  "

    run_task

    assert User.exists?(email_address: "owner@example.com")
  end

  test "admin:create should match an existing account whatever the casing" do
    user = create(:user, email_address: "owner@example.com", name: "Original")
    ENV["EMAIL"] = "  Owner@Example.COM "

    run_task

    assert_equal "Original", user.reload.name
    assert_equal 1, User.where(email_address: "owner@example.com").count
  end

  test "admin:create should warn when the account can't sign in" do
    create(:user, :suspended, email_address: "owner@example.com")
    ENV["EMAIL"] = "owner@example.com"

    assert_includes run_task(stream: :err), "suspended"
  end

  test "admin:create should abort without an email address" do
    assert_raises(SystemExit) { run_task }
  end

  private

  def run_task(stream: :out)
    out, err = capture_io { @task.invoke }
    stream == :err ? err : out
  end
end
