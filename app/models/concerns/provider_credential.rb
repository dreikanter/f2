# Shared behavior for the provider credential types (AI and web search). Both
# wrap a user-owned API key in the same pending → validating → active|inactive
# lifecycle, name themselves after their provider, and take their feeds down
# with them when deactivated or destroyed.
#
# Including models declare their provider vocabulary, the event types they
# record, and their own domain logic; everything else derives from the model
# name.
module ProviderCredential
  extend ActiveSupport::Concern

  DISPLAY_NAME_MAX_LENGTH = 80
  VALIDATION_TIMEOUT = 15.minutes

  included do
    include HasOperationRuns

    belongs_to :user
    # `dependent` is handled manually by `disable_dependent_feeds` so we can
    # both nullify the reference and pull any feed left enabled out of the
    # enabled state in one pass.
    has_many :feeds

    # Rails 8 stores the encryption envelope as a JSON object
    # ({"h": {...}, "p": "<ciphertext>"}) which `jsonb` accepts natively.
    # The raw column contains only the envelope; the API key is never
    # stored in plaintext.
    encrypts :credential_data

    enum :state, { pending: 0, validating: 1, active: 2, inactive: 3 }

    validates :display_name,
              presence: true,
              length: { maximum: DISPLAY_NAME_MAX_LENGTH },
              uniqueness: { scope: [:user_id, :provider] }

    validate :api_key_present

    before_validation :assign_name_if_blank, on: :create
    before_destroy :disable_dependent_feeds
  end

  def default?
    user.public_send(:"default_#{param_key}_id") == id
  end

  def make_default!
    user.update!("default_#{param_key}": self)
  end

  # Opens a fresh run before enqueueing so a queue stall is covered by the same
  # timeout as a worker that disappears after starting.
  def validate_async(validation_job)
    fallback_state = active? ? :active : :inactive
    run = OperationRun.start!(
      subject: self,
      kind: :validation,
      timeout: VALIDATION_TIMEOUT,
      context: { fallback_state: fallback_state }
    ) do |credential|
      credential.update!(state: :validating, last_error: nil)
    end

    validation_job.perform_later(run)
    ProviderCredentialValidationTimeoutJob
      .set(wait_until: run.deadline_at)
      .perform_later(run)
    run
  end

  # Takes the credential and everything depending on it out of service in one
  # transaction: a key that just failed cannot back a running feed.
  def deactivate!(last_error: nil, run: nil)
    if run
      return false unless run.subject == self

      return run.fail! { deactivate_locked!(last_error: last_error) }
    end

    with_lock { deactivate_locked!(last_error: last_error) }
  end

  private

  def deactivate_locked!(last_error:)
    update!(state: :inactive, last_validated_at: Time.current, last_error: last_error)

    Event.create!(
      type: self.class::DEACTIVATED_EVENT_TYPE,
      level: :warning,
      subject: self,
      user: user
    )

    feeds.where(state: Feed.states[:enabled]).update_all(state: Feed.states[:disabled])
    true
  end

  # Names the feed foreign key and the user's `default_*` columns alike.
  def param_key
    self.class.model_name.param_key
  end

  def assign_name_if_blank
    return if display_name.present? || provider.blank?

    self.display_name = generate_unique_name
  end

  def generate_unique_name
    existing = self.class.where(user_id: user_id, provider: provider).pluck(:display_name).map(&:downcase).to_set
    CredentialNameGenerator.new(provider, existing).generate.split.map(&:capitalize).join(" ")
  end

  def api_key_present
    return if provider.blank?

    errors.add(:base, "Enter your API key") if credential_data.blank? || credential_data["api_key"].blank?
  end

  # Detach this credential from every dependent feed. Enabled feeds reuse the
  # feed's generic disable-and-event transition; drafts and already-disabled
  # feeds keep their state and receive a removal-only event.
  def disable_dependent_feeds
    feeds.find_each do |feed|
      feed.update_column(:"#{param_key}_id", nil)
      next if feed.enabled? && feed.disable_with_event!(self.class::REMOVED_EVENT_TYPE, { disabled: true })

      Event.create!(
        type: self.class::REMOVED_EVENT_TYPE,
        level: :warning,
        subject: feed,
        user: user,
        metadata: { disabled: false }
      )
    end
  end
end
