require "test_helper"

class WithdrawAllPostsJobTest < ActiveJob::TestCase
  def user
    @user ||= create(:user)
  end

  def access_token
    @access_token ||= create(:access_token, :active, user: user)
  end

  def feed
    @feed ||= create(:feed, user: user, access_token: access_token, target_group: "testgroup")
  end

  test ".perform_now should delegate to WithdrawAllPosts" do
    called_with = nil
    fake = Struct.new(:call).new(nil)
    WithdrawAllPosts.stub(:new, ->(f) { called_with = f; fake }) do
      WithdrawAllPostsJob.perform_now(feed.id)
    end

    assert_equal feed, called_with
  end

  test ".perform_now should exit gracefully if feed not found" do
    assert_nothing_raised do
      WithdrawAllPostsJob.perform_now(999999)
    end
  end

  test ".perform_now should exit gracefully if access token is inactive" do
    feed.access_token.update!(status: :inactive)
    service_called = false
    WithdrawAllPosts.stub(:new, ->(_) { service_called = true }) do
      WithdrawAllPostsJob.perform_now(feed.id)
    end

    assert_not service_called
  end
end
