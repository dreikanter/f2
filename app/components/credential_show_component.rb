# A provider credential's detail page. The frame is the same for every
# credential type: a header, the delete modal, a body that depends on whether
# the key has been checked yet, and the way back to a feed that detoured here.
# What differs arrives as slots and copy.
class CredentialShowComponent < ViewComponent::Base
  # The credential's detail table, shown once the key has a verdict.
  renders_one :details
  # Shown after the details for an active credential only.
  renders_one :active_extra
  # Shown once the key has a verdict, whichever way it went.
  renders_one :settled_extra

  # @param credential [ApplicationRecord] the credential being shown
  # @param key [String] the page's test hook namespace
  # @param breadcrumb [String] label for the index breadcrumb
  # @param breadcrumb_url [String] path to the index
  # @param checking_note [String] what to expect while the key is checked
  # @param rejected_note [String] fallback copy when the key was refused
  # @param feed_id [String, nil] the draft feed that detoured here, if any
  def initialize(credential:, key:, breadcrumb:, breadcrumb_url:, checking_note:, rejected_note:, feed_id: nil)
    @credential = credential
    @key = key
    @breadcrumb = breadcrumb
    @breadcrumb_url = breadcrumb_url
    @checking_note = checking_note
    @rejected_note = rejected_note
    @feed_id = feed_id
  end

  private

  attr_reader :credential, :key, :breadcrumb, :breadcrumb_url, :checking_note, :rejected_note, :feed_id

  def menu_id
    "#{key.dasherize}-header-menu-#{credential.id}"
  end

  def settled?
    credential.active? || credential.inactive?
  end
end
