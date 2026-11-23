module AccountRbacAssociations
  extend ActiveSupport::Concern

  included do
    has_many :rbac_roles, dependent: :delete_all
    has_many :rbac_audit_events, dependent: :delete_all
    before_destroy :clear_rbac_role_assignments, prepend: true
  end

  private

  def clear_rbac_role_assignments
    # Account teardown must clear the restrictive composite FK before async membership deletion.
    # rubocop:disable Rails/SkipsModelValidations
    account_users.where.not(rbac_role_id: nil).update_all(rbac_role_id: nil)
    # rubocop:enable Rails/SkipsModelValidations
  end
end
