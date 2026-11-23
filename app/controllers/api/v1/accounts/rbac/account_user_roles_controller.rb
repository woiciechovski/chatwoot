class Api::V1::Accounts::Rbac::AccountUserRolesController < Api::V1::Accounts::Rbac::BaseController
  def update
    account_user = role_management_service.assign_role!(
      account_user_id: params[:account_user_id],
      role_id: params.require(:role_id)
    )
    render json: serialize_account_user(account_user)
  end

  def destroy
    account_user = role_management_service.remove_role!(account_user_id: params[:account_user_id])
    render json: serialize_account_user(account_user)
  end

  private

  def serialize_account_user(account_user)
    {
      account_user_id: account_user.id,
      role_id: account_user.rbac_role_id,
      managed: account_user.rbac_managed
    }
  end
end
