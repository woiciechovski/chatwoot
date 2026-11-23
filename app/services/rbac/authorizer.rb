class Rbac::Authorizer
  STATES = %i[invalid legacy legacy_for_unmigrated_domain enforced_rbac native_administrator].freeze

  def self.allowed?(account_user:, permission:, resource: nil)
    return false unless valid_access_request?(account_user, permission, resource)

    state = state_for(account_user: account_user, permission: permission)
    return true if state.in?([:legacy, :legacy_for_unmigrated_domain, :native_administrator])
    return false unless state == :enforced_rbac

    assignable_grant?(account_user, permission)
  end

  def self.state_for(account_user:, permission:)
    entry = Rbac::Catalog.find(permission)
    return :invalid unless entry && valid_account_user?(account_user)
    return :native_administrator if account_user.administrator?

    agent_state(account_user, entry)
  end

  def self.valid_account_user?(account_user)
    return false unless account_user.is_a?(AccountUser) && account_user.persisted? && account_user.account_id.present?
    return false if Current.account.present? && Current.account.id != account_user.account_id

    true
  end

  def self.valid_access_request?(account_user, permission, resource)
    Rbac::Catalog.find(permission).present? && valid_account_user?(account_user) &&
      resource_belongs_to_account?(resource, account_user.account_id)
  end

  def self.resource_belongs_to_account?(resource, account_id)
    return true if resource.nil?
    return false unless resource.respond_to?(:account_id)

    resource.account_id == account_id
  end

  def self.agent_state(account_user, entry)
    return :invalid unless account_user.agent?
    return :legacy if account_user.rbac_role_id.blank? && !account_user.rbac_managed?
    return :legacy_for_unmigrated_domain if entry[:status] == 'planned'
    return :invalid unless entry[:status] == 'enforced'

    :enforced_rbac
  end

  def self.assignable_grant?(account_user, permission)
    role = account_user.rbac_role
    return false if role.blank? || !role.active? || role.account_id != account_user.account_id

    grant = role_permission(role, permission)
    grant.present? && Rbac::Catalog.scope_allowed?(permission, grant.scope_type) && grant.scope_type == 'all_in_account'
  end

  def self.role_permission(role, permission)
    return role.role_permissions.find_by(permission_key: permission) unless role.role_permissions.loaded?

    role.role_permissions.find { |role_permission| role_permission.permission_key == permission }
  end

  private_class_method :valid_access_request?, :resource_belongs_to_account?, :agent_state, :assignable_grant?,
                       :role_permission
end
