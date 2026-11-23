class Rbac::RoleManagementService
  class StaleVersionError < StandardError; end
  class InvalidVersionError < StandardError; end

  class NotAuthorizedError < StandardError
    attr_reader :audit_actor, :audit_account

    def initialize(audit_actor:, audit_account:)
      @audit_actor = audit_actor
      @audit_account = audit_account
      super()
    end
  end

  class SelfAssignmentNotAllowed < StandardError
    attr_reader :audit_actor, :audit_account

    def initialize(audit_actor:, audit_account:)
      @audit_actor = audit_actor
      @audit_account = audit_account
      super()
    end
  end

  class InactiveRoleError < StandardError; end
  class InvalidRoleAttributesError < StandardError; end
  class InvalidGrantsError < StandardError; end

  ROLE_ATTRIBUTES = %i[name description active].freeze
  MAX_EXPECTED_VERSION = 2_147_483_647

  def initialize(account:, actor:, request_id: nil)
    @account = account
    @actor = actor
    @request_id = request_id
  end

  def create_role!(attributes)
    permitted_attributes = attributes.to_h.symbolize_keys.slice(*ROLE_ATTRIBUTES)

    Rbac::MembershipLockService.with_account(account_id: @account.id) do |account|
      ensure_admin!
      role = account.rbac_roles.create!(permitted_attributes)
      record_success(
        action: 'role.created',
        target: role,
        details: { name: role.name, changed_fields: permitted_attributes.keys.map(&:to_s) }
      )
      role
    end
  end

  def update_role!(role_id:, attributes:, expected_version:)
    permitted_attributes = attributes.to_h.symbolize_keys.slice(*ROLE_ATTRIBUTES)

    Rbac::MembershipLockService.with_account(account_id: @account.id) do |account|
      ensure_admin!
      role = account.rbac_roles.find(role_id)
      role.with_lock do
        verify_expected_version!(role, expected_version)
        role.update!(permitted_attributes)
        record_success(
          action: 'role.updated',
          target: role,
          details: Rbac::AuditEvents::RoleChanges.for_update(role, permitted_attributes)
        )
        role
      end
    end
  end

  def delete_role!(role_id:, expected_version:)
    Rbac::MembershipLockService.with_account(account_id: @account.id) do |account|
      ensure_admin!
      role = account.rbac_roles.find(role_id)

      role.with_lock do
        verify_expected_version!(role, expected_version)
        role.destroy!
        record_success(action: 'role.deleted', target: role, details: { name: role.name })
      end
    end
  end

  def replace_grants!(role_id:, grants:, expected_version:)
    Rbac::MembershipLockService.with_account(account_id: @account.id) do |account|
      ensure_admin!
      role = account.rbac_roles.find(role_id)

      role.with_lock do
        verify_expected_version!(role, expected_version)
        replace_role_grants(role, grants)
      end
    end
  end

  def assign_role!(account_user_id:, role_id:)
    account_user = @account.account_users.find(account_user_id)
    role = @account.rbac_roles.find(role_id)

    Rbac::MembershipLockService.with_membership(
      account_id: @account.id,
      user_id: account_user.user_id,
      membership_id: account_user.id
    ) do |_locked_account, _locked_user, locked_account_user|
      ensure_admin!
      prevent_self_assignment!(locked_account_user)
      assign_role_to_membership!(locked_account_user, role)
    end
  end

  def remove_role!(account_user_id:)
    account_user = @account.account_users.find(account_user_id)

    Rbac::MembershipLockService.with_membership(
      account_id: @account.id,
      user_id: account_user.user_id,
      membership_id: account_user.id
    ) do |_locked_account, _locked_user, locked_account_user|
      ensure_admin!
      previous_role_id = locked_account_user.rbac_role_id
      locked_account_user.update!(rbac_role: nil)
      record_success(action: 'role.removed', target: locked_account_user, details: { previous_role_id: previous_role_id })
      locked_account_user
    end
  end

  private

  def ensure_admin!
    return if refresh_actor_if_administrator

    audit_actor = if @actor.is_a?(AccountUser) && @actor.account_id != @account.id
                    Current.user
                  else
                    @actor
                  end
    raise NotAuthorizedError.new(audit_actor: audit_actor, audit_account: @account)
  end

  def refresh_actor_if_administrator
    return false unless @actor.is_a?(AccountUser) && @actor.persisted? && @actor.account_id == @account.id

    current_actor = AccountUser.find_by(id: @actor.id, account_id: @account.id)
    return false unless current_actor&.administrator?

    @actor = current_actor
    true
  end

  def prevent_self_assignment!(account_user)
    return unless @actor.id == account_user.id

    raise SelfAssignmentNotAllowed.new(audit_actor: @actor, audit_account: @account)
  end

  def assign_role_to_membership!(account_user, role)
    role.with_lock do
      raise InactiveRoleError unless role.active?

      previous_role_id = account_user.rbac_role_id
      account_user.update!(rbac_role: role)
      record_success(
        action: 'role.assigned',
        target: account_user,
        details: { previous_role_id: previous_role_id, role_id: role.id }
      )
      account_user
    end
  end

  def replace_role_grants(role, grants)
    previous_grants = role.role_permissions.order(:permission_key).map do |grant|
      { permission_key: grant.permission_key, scope_type: grant.scope_type }
    end
    role.role_permissions.destroy_all
    grants.each do |grant|
      role.role_permissions.create!(grant.to_h.symbolize_keys.slice(:permission_key, :scope_type))
    end
    role.update!(updated_at: Time.current)
    record_success(
      action: 'role.grants_replaced',
      target: role,
      details: Rbac::AuditEvents::RoleChanges.for_grants(previous_grants, grants)
    )
    role
  end

  def verify_expected_version!(role, expected_version)
    version = parse_expected_version(expected_version)
    raise StaleVersionError unless role.lock_version == version
  end

  def parse_expected_version(expected_version)
    if expected_version.is_a?(Integer)
      return expected_version if expected_version.between?(0, MAX_EXPECTED_VERSION)
    elsif expected_version.is_a?(String) && expected_version.match?(/\A[0-9]+\z/)
      version = expected_version.to_i
      return version if version <= MAX_EXPECTED_VERSION
    end

    raise InvalidVersionError
  end

  def record_success(action:, target:, details: {})
    Rbac::AuditEvents::Recorder.record!(
      account: @account,
      actor: @actor,
      action: action,
      target: target,
      metadata: { details: details, request_id: @request_id }
    )
  end
end
