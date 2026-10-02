class User < ApplicationRecord
  belongs_to :kindergarten, optional: true

  has_secure_password reset_token: false

  enum :role, { kindergarten: "kindergarten", center: "center" }, validate: true

  validates :login_id, presence: true, uniqueness: true
  validates :kindergarten_id, uniqueness: true, allow_nil: true
  validates :kindergarten, presence: true, if: :kindergarten?
  validates :kindergarten, :kindergarten_id, absence: true, if: :center?
end
