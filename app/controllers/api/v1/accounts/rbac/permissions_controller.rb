class Api::V1::Accounts::Rbac::PermissionsController < Api::V1::Accounts::Rbac::BaseController
  def index
    render json: { permissions: Rbac::Catalog.entries }
  end
end
