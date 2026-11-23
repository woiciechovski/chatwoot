class RbacRolePermission < ApplicationRecord
  belongs_to :rbac_role, inverse_of: :role_permissions

  validates :permission_key, presence: true
  validates :scope_type, presence: true
  validates :permission_key, uniqueness: { scope: :rbac_role_id }
  validate :permission_is_assignable
  validate :scope_is_supported

  private

  def permission_is_assignable
    return if Rbac::Catalog.assignable?(permission_key)

    errors.add(:permission_key, I18n.t('errors.rbac_role_permission.not_assignable'))
  end

  def scope_is_supported
    return if Rbac::Catalog.scope_allowed?(permission_key, scope_type)

    errors.add(:scope_type, I18n.t('errors.rbac_role_permission.unsupported_scope'))
  end
end
