class Api::V1::Accounts::Rbac::BaseController < Api::V1::Accounts::BaseController
  AUDIT_ACTIONS = {
    'roles#index' => 'role.read',
    'roles#show' => 'role.read',
    'roles#create' => 'role.create',
    'roles#update' => 'role.update',
    'roles#destroy' => 'role.delete',
    'roles#grants' => 'role.grants_replace',
    'permissions#index' => 'permissions.read',
    'audit_events#index' => 'audit_events.read',
    'account_user_roles#update' => 'role.assign',
    'account_user_roles#destroy' => 'role.remove'
  }.freeze

  before_action :authorize_rbac_admin!

  rescue_from ActiveRecord::RecordNotDestroyed, with: :render_rbac_record_not_destroyed
  rescue_from Rbac::RoleManagementService::StaleVersionError, with: :render_stale_version
  rescue_from Rbac::RoleManagementService::InvalidVersionError, with: :render_invalid_version
  rescue_from Rbac::RoleManagementService::NotAuthorizedError, with: :render_rbac_not_authorized
  rescue_from Rbac::RoleManagementService::SelfAssignmentNotAllowed, with: :render_rbac_self_assignment_denied
  rescue_from Rbac::RoleManagementService::InactiveRoleError, with: :render_inactive_role
  rescue_from Rbac::RoleManagementService::InvalidRoleAttributesError, with: :render_invalid_role_attributes
  rescue_from Rbac::RoleManagementService::InvalidGrantsError, with: :render_invalid_grants

  private

  def render_not_found_error(message)
    record_denied_attempt
    super
  end

  def authorize_rbac_admin!
    @rbac_audit_account = Current.account
    @rbac_audit_actor = audit_actor_for(@rbac_audit_account)
    authorize(RbacRole, :manage?)
  rescue Pundit::NotAuthorizedError
    record_denied_attempt
    raise
  end

  def role_management_service
    Rbac::RoleManagementService.new(account: Current.account, actor: Current.account_user, request_id: request.request_id)
  end

  def serialize_role(role)
    {
      id: role.id,
      name: role.name,
      description: role.description,
      active: role.active,
      lock_version: role.lock_version,
      grants: role.role_permissions.sort_by(&:permission_key).map do |grant|
        { permission_key: grant.permission_key, scope_type: grant.scope_type }
      end
    }
  end

  def record_denied_attempt(actor: nil, account: nil)
    account ||= Current.account || @rbac_audit_account
    actor ||= @rbac_audit_actor || audit_actor_for(account)
    return if account.blank?

    Rbac::AuditEvents::Recorder.record_denied_safely!(
      account: account,
      actor: actor,
      action: "#{rbac_audit_action}.denied",
      target_type: audit_target_type,
      target_id: audit_target_id(account),
      metadata: { request_id: request.request_id }
    )
  end

  def rbac_audit_action
    AUDIT_ACTIONS.fetch("#{controller_name}##{action_name}", 'rbac.manage')
  end

  def audit_actor_for(account)
    account_user = Current.account_user
    return account_user if account && account_user&.account_id == account.id

    Current.user
  end

  def audit_target_type
    case controller_name
    when 'account_user_roles' then 'AccountUser'
    when 'audit_events' then 'RbacAuditEvent'
    else 'RbacRole'
    end
  end

  def audit_target_id(account)
    case controller_name
    when 'account_user_roles'
      account.account_users.where(id: params[:account_user_id]).pick(:id)
    when 'roles'
      account.rbac_roles.where(id: params[:id]).pick(:id)
    end
  end

  def render_stale_version
    render json: { error: { code: 'stale_version', message: 'The role has changed. Reload it and retry.' } }, status: :conflict
  end

  def render_invalid_version
    render json: {
      error: { code: 'invalid_version', message: 'expected_version must be an integer or ASCII decimal string from 0 to 2147483647.' }
    }, status: :unprocessable_entity
  end

  def render_rbac_record_not_destroyed(exception)
    record = exception.record
    render json: { message: record.errors.full_messages.join(', '), attributes: record.errors.attribute_names },
           status: :unprocessable_entity
  end

  def render_rbac_self_assignment_denied(exception)
    record_denied_attempt(actor: exception.audit_actor, account: exception.audit_account)
    render json: { error: { code: 'self_assignment_not_allowed', message: 'A role cannot be assigned to the current administrator.' } },
           status: :unprocessable_entity
  end

  def render_rbac_not_authorized(exception)
    record_denied_attempt(actor: exception.audit_actor, account: exception.audit_account)
    render json: { error: { code: 'not_authorized', message: 'The current account user cannot manage this RBAC change.' } },
           status: :unauthorized
  end

  def render_inactive_role
    render json: { error: { code: 'inactive_role', message: 'Only active roles can be assigned.' } }, status: :unprocessable_entity
  end

  def render_invalid_role_attributes
    render json: { error: { code: 'invalid_role_attributes', message: 'role must be an object.' } }, status: :unprocessable_entity
  end

  def render_invalid_grants
    render json: { error: { code: 'invalid_grants', message: 'grants must be an array of grant objects.' } }, status: :unprocessable_entity
  end
end
