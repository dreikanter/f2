class Invite < ApplicationRecord
  belongs_to :created_by_user, class_name: "User"
  belongs_to :invited_user, class_name: "User", optional: true

  validates :created_by_user, presence: true

  def used?
    invited_user_id.present?
  end
end
