class Onboarding < ApplicationRecord
  belongs_to :user
  belongs_to :access_token, optional: true
  belongs_to :feed, optional: true
end
