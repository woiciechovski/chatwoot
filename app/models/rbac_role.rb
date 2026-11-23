class RbacRole < ApplicationRecord
  belongs_to :account

  has_many :role_permissions, class_name: 'RbacRolePermission', dependent: :destroy, inverse_of: :rbac_role
  has_many :account_users, inverse_of: :rbac_role, dependent: :restrict_with_error

  before_validation :normalize_name

  validates :name, presence: true, length: { maximum: 100 }
  validates :active, inclusion: { in: [true, false] }
  validate :normalized_name_is_unique_within_account

  private

  def normalize_name
    self.normalized_name = name.to_s.strip.downcase
  end

  def normalized_name_is_unique_within_account
    return if account_id.blank? || normalized_name.blank?
    return unless self.class.where(account_id: account_id, normalized_name: normalized_name).where.not(id: id).exists?

    errors.add(:name, :taken)
  end
end
