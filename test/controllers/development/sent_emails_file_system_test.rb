require "test_helper"

# The sent-emails pages run on the :file_system adapter in staging and
# production, but the main controller test exercises :in_memory. Drive the real
# controller and views through a FileSystemStorage to cover that path.
class Development::SentEmailsFileSystemTest < ActionDispatch::IntegrationTest
  setup do
    FileUtils.mkdir_p(storage_dir)
    login_as(dev_user)
  end

  teardown do
    FileUtils.rm_rf(storage_dir)
  end

  def storage_dir
    @storage_dir ||= Rails.root.join("tmp", "test_sent_emails_#{SecureRandom.hex(8)}")
  end

  def storage
    @storage ||= EmailStorage::FileSystemStorage.new(storage_dir)
  end

  def dev_user
    @dev_user ||= create(:user, :dev)
  end

  test "#index should render with no captured emails" do
    with_file_system_storage do
      get development_sent_emails_path
    end

    assert_response :success
    assert_select '[data-key="development.emails.empty"]', text: /No emails captured yet/
  end

  test "#index should render captured emails" do
    save_email("Welcome aboard")
    save_email("Reset your password")

    with_file_system_storage do
      get development_sent_emails_path
    end

    assert_response :success
    assert_select '[data-key="development.emails.list.item"]', count: 2
    assert_select '[data-key="development.emails.list.item"] a', text: "Welcome aboard"
  end

  test "#show should render a captured email" do
    save_email("Welcome aboard", "Glad you're here")
    uuid = storage.list.first[:id]

    with_file_system_storage do
      get development_sent_email_path(id: uuid)
    end

    assert_response :success
    assert_select '[data-key="development.emails.subject"]', text: "Welcome aboard"
    assert_select '[data-key="development.emails.body"]', text: /Glad you're here/
  end

  test "#purge should clear captured emails" do
    save_email("Welcome aboard")

    with_file_system_storage do
      delete purge_development_sent_emails_path
    end

    assert_redirected_to development_sent_emails_path
    assert_equal 0, storage.list.count
  end

  private

  def with_file_system_storage(&block)
    EmailStorageResolver.stub(:resolve, storage, &block)
  end

  def save_email(subject, body = "Body text")
    storage.save_email(
      metadata: {
        "message_id" => "<#{SecureRandom.hex(8)}@example.com>",
        "from" => "sender@example.com",
        "to" => "recipient@example.com",
        "subject" => subject,
        "date" => Time.current,
        "timestamp" => Time.current,
        "multipart" => false
      },
      text_content: body
    )
  end

  def login_as(user)
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end
end
