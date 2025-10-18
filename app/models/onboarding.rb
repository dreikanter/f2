class Onboarding < ApplicationRecord
  belongs_to :user
  belongs_to :access_token, optional: true
  belongs_to :feed, optional: true

  def token_setup?
    access_token_id.nil?
  end

  def feed_setup?
    access_token_id.present? && feed_id.nil?
  end
end
