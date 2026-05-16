# HMAC-signed token tying a successful preview to a subsequent feed save.
#
# The token binds (user_id, profile_key, params_digest, generated_at) so that
# Feed#enabling_requires_recent_preview can verify the user actually saw a
# preview for the exact (profile, params) they're about to save.
#
# Tokens expire EXPIRY seconds after generated_at.
class PreviewToken
  EXPIRY = 60.minutes

  class << self
    # @return [String] a base64url-encoded token
    def sign(user_id:, profile_key:, params:, generated_at:)
      payload = encode_payload(user_id, profile_key, params, generated_at.to_i)
      signature = compute_signature(payload)
      "#{payload}.#{signature}"
    end

    # @return [Boolean] true if token matches the given (user_id, profile_key, params) and is not expired
    def verify(token, user_id:, profile_key:, params:)
      return false if token.blank?

      payload, signature = token.to_s.split(".", 2)
      return false if payload.blank? || signature.blank?

      expected_signature = compute_signature(payload)
      return false unless ActiveSupport::SecurityUtils.secure_compare(signature, expected_signature)

      decoded = decode_payload(payload)
      return false unless decoded

      decoded_user_id, decoded_profile_key, decoded_params_digest, decoded_generated_at = decoded
      return false unless decoded_user_id == user_id
      return false unless decoded_profile_key == profile_key
      return false unless decoded_params_digest == params_digest(params)
      return false if Time.current.to_i - decoded_generated_at >= EXPIRY.to_i

      true
    rescue ArgumentError
      false
    end

    private

    def encode_payload(user_id, profile_key, params, generated_at_i)
      data = [user_id, profile_key, params_digest(params), generated_at_i].join("|")
      Base64.urlsafe_encode64(data, padding: false)
    end

    def decode_payload(payload)
      raw = Base64.urlsafe_decode64(payload)
      user_id, profile_key, params_digest, generated_at = raw.split("|", 4)
      return nil if user_id.nil? || profile_key.nil? || params_digest.nil? || generated_at.nil?

      [Integer(user_id), profile_key, params_digest, Integer(generated_at)]
    end

    def params_digest(params)
      canonical = (params || {}).deep_stringify_keys.sort.to_h.to_json
      Digest::SHA256.hexdigest(canonical)
    end

    def compute_signature(payload)
      OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, payload)
    end
  end
end
