class Platform::Api::V1::AccountUsersController < PlatformController
  before_action :set_resource
  before_action :validate_platform_app_permissible

  def index
    render json: @resource.account_users
  end

  def create
    account = @resource
    actor = @platform_app
    user_id = account_user_params[:user_id]
    Rbac::MembershipLockService.with_account(account_id: @resource.id) do |locked_account|
      existing_membership = locked_account.account_users.find_by(user_id: user_id)
      Rbac::MembershipLockService.with_membership(
        account_id: locked_account.id,
        user_id: user_id,
        membership_id: existing_membership&.id
      ) do |_locked_account, user, locked_membership|
        @account_user = locked_membership || AccountUser.new(account: locked_account, user: user)
        @account_user.update!(role: account_user_params[:role])
      end
    end
    render json: @account_user
  rescue ActiveRecord::RecordInvalid => e
    record_denied_administrator_demotion(e.record, account, actor)
    raise
  end

  def destroy
    Rbac::MembershipLockService.with_account(account_id: @resource.id) do |account|
      membership = account.account_users.find_by(user_id: account_user_params[:user_id])
      next unless membership

      Rbac::MembershipLockService.with_membership(
        account_id: account.id,
        user_id: membership.user_id,
        membership_id: membership.id
      ) do |_locked_account, _user, locked_membership|
        locked_membership.destroy!
      end
    end
    head :ok
  rescue ActiveRecord::RecordNotDestroyed => e
    record_denied_administrator_removal(e.record)
    render json: { message: e.record.errors.full_messages.join(', '), attributes: e.record.errors.attribute_names },
           status: :unprocessable_entity
  end

  private

  def set_resource
    @resource = Account.find(params[:account_id])
  end

  def account_user_params
    params.permit(:user_id, :role)
  end

  def record_denied_administrator_demotion(account_user, account, actor)
    return unless account_user.errors.details.values.flatten.any? { |detail| detail[:error] == :last_administrator }

    Rbac::AuditEvents::Recorder.record_denied_safely!(
      account: account,
      actor: actor,
      action: 'administrator.demotion.denied',
      target_type: 'AccountUser',
      target_id: account_user.id,
      metadata: { request_id: request.request_id }
    )
  end

  def record_denied_administrator_removal(account_user)
    return unless account_user.errors.details.values.flatten.any? { |detail| detail[:error] == :last_administrator }

    Rbac::AuditEvents::Recorder.record_denied_safely!(
      account: @resource,
      actor: @platform_app,
      action: 'administrator.removal.denied',
      target_type: 'AccountUser',
      target_id: account_user.id,
      metadata: { request_id: request.request_id }
    )
  end
end
