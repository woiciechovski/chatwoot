class Api::V1::Accounts::Rbac::RolesController < Api::V1::Accounts::Rbac::BaseController
  def index
    roles = Current.account.rbac_roles.includes(:role_permissions).order(:normalized_name)
    render json: roles.map { |role| serialize_role(role) }
  end

  def show
    render json: serialize_role(roles.find(params[:id]))
  end

  def create
    role = role_management_service.create_role!(role_params)
    render json: serialize_role(role), status: :created
  end

  def update
    role = role_management_service.update_role!(
      role_id: params[:id],
      attributes: role_params,
      expected_version: params[:expected_version]
    )
    render json: serialize_role(role)
  end

  def destroy
    role_management_service.delete_role!(role_id: params[:id], expected_version: params[:expected_version])
    head :no_content
  end

  def grants
    role = role_management_service.replace_grants!(
      role_id: params[:id],
      grants: grant_params,
      expected_version: params[:expected_version]
    )
    render json: serialize_role(role)
  end

  private

  def roles
    Current.account.rbac_roles
  end

  def role_params
    role = params.require(:role)
    raise Rbac::RoleManagementService::InvalidRoleAttributesError unless role.is_a?(ActionController::Parameters)

    role.permit(:name, :description, :active)
  end

  def grant_params
    grants = params[:grants]
    raise ActionController::ParameterMissing, :grants if grants.nil?
    raise Rbac::RoleManagementService::InvalidGrantsError unless grants.is_a?(Array) && grants.all?(ActionController::Parameters)

    grants.map { |grant| grant.permit(:permission_key, :scope_type) }
  end
end
