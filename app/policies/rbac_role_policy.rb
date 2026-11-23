class RbacRolePolicy < ApplicationPolicy
  def manage?
    account_user.is_a?(AccountUser) && account_user.administrator? && account_user.account_id == account&.id
  end
end
