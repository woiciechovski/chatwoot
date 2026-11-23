class Api::V1::Accounts::BaseController < Api::BaseController
  include SwitchLocale
  include EnsureCurrentAccountHelper
  include MfaEnforcementGuard
  before_action :current_account
  before_action :validate_token_api_access, if: :authenticate_by_access_token?
  before_action :check_account_mfa_enforcement, if: :authenticate_by_access_token?
  around_action :switch_locale_using_account_locale

  private

  def validate_bot_access_token!
    record_rbac_non_human_principal_denial if rbac_admin_endpoint? && !Current.user.is_a?(User)
    super
  end

  def record_rbac_non_human_principal_denial
    account = Account.find_by(id: params[:account_id])
    actor = @resource
    return if account.blank? || actor.blank? || !principal_can_access_rbac_account?(actor, account)

    Rbac::AuditEvents::Recorder.record_denied_safely!(
      account: account,
      actor: actor,
      action: 'rbac.technical_principal.denied',
      target_type: 'RbacRole',
      metadata: { request_id: request.request_id }
    )
  end

  def principal_can_access_rbac_account?(actor, account)
    if actor.is_a?(AgentBot)
      actor.account_id == account.id || actor.agent_bot_inboxes.exists?(account_id: account.id)
    elsif actor.is_a?(PlatformApp)
      actor.platform_app_permissibles.exists?(permissible: account)
    else
      false
    end
  end

  def rbac_admin_endpoint?
    params[:controller].to_s.start_with?('api/v1/accounts/rbac/')
  end

  def administrator_api_token?
    @access_token.present? && Current.account_user&.administrator?
  end

  def validate_token_api_access
    return if Current.account.api_and_webhooks_enabled?

    render json: { error: 'API access is not enabled for this account' }, status: :forbidden
  end
end
