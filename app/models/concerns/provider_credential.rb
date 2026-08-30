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
    started_at = Time.current
    run_id = SecureRandom.uuid

    update!(
      state: :validating,
      last_error: nil,
      validation_started_at: started_at,
      validation_run_id: run_id
    )
    validation_job.perform_later(self, run_id, fallback_state.to_s)
    ProviderCredentialValidationTimeoutJob
      .set(wait_until: started_at + VALIDATION_TIMEOUT)
      .perform_later(self, run_id, fallback_state.to_s)
    run_id
  end

  # @param run_id [String] UUID captured by the worker
  # @return [Boolean] whether the worker owns the current run
  def validation_run?(run_id)
    self.class.where(id: id, validation_run_id: run_id).exists?
  end

  # @param run_id [String] UUID captured by the worker
  # @param state [Symbol, String] terminal state
  # @param attributes [Hash] additional terminal attributes
  # @return [Boolean] whether the matching run was settled
  def settle_validation!(run_id:, state:, **attributes)
    with_lock do
      return false unless validation_run_id == run_id

      update!(
        **attributes,
        state: state,
        validation_started_at: nil,
        validation_run_id: nil
      )
    end

    true
  end

  # @param run_id [String] UUID captured by the timeout job
  # @param fallback_state [String] state to restore without judging the key
  # @return [Boolean] whether the matching run was settled
  def timeout_validation!(run_id:, fallback_state:)
    settle_validation!(run_id: run_id, state: fallback_state)
  end

  # Takes the credential and everything depending on it out of service in one
  # transaction: a key that just failed cannot back a running feed.
  def deactivate!(last_error: nil, run_id: nil)
    with_lock do
      return false if run_id && validation_run_id != run_id

      update!(
        state: :inactive,
        last_validated_at: Time.current,
        last_error: last_error,
        validation_started_at: nil,
        validation_run_id: nil
      )

      Event.create!(
        type: self.class::DEACTIVATED_EVENT_TYPE,
        level: :warning,
        subject: self,
        user: user
      )

      feeds.where(state: Feed.states[:enabled]).update_all(state: Feed.states[:disabled])
    end

    true
  end

  private

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
