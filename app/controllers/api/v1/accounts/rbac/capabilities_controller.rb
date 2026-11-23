class Api::V1::Accounts::Rbac::CapabilitiesController < Api::V1::Accounts::BaseController
  def show
    current_account_user = account_user
    render json: {
      account_user_id: current_account_user.id,
      native_role: current_account_user.role,
      role: serialize_role(current_account_user.rbac_role),
      domains: serialized_domains(current_account_user)
    }
  end

  private

  def account_user
    account_user = Current.account_user
    return account_user if account_user.is_a?(AccountUser) && account_user.account_id == Current.account.id

    raise Pundit::NotAuthorizedError
  end

  def serialize_role(role)
    return if role.blank?

    {
      id: role.id,
      name: role.name,
      active: role.active,
      grants: role.role_permissions.order(:permission_key).map do |grant|
        { permission_key: grant.permission_key, scope_type: grant.scope_type }
      end
    }
  end

  def serialized_domains(account_user)
    Rbac::Catalog.entries.group_by { |entry| entry[:module] }.map do |module_name, entries|
      domain = {
        module: module_name,
        status: domain_status(entries),
        authorization_state: Rbac::Authorizer.state_for(account_user: account_user, permission: entries.first[:key]),
        permissions: entries.pluck(:key)
      }
      domain[:capabilities] = contact_capabilities(account_user) if module_name == 'contacts'
      domain
    end
  end

  def contact_capabilities(account_user)
    policy_context = { user: account_user.user, account: account_user.account, account_user: account_user }
    contact_policy = ContactPolicy.new(policy_context, Contact)
    {
      'contacts.read' => contact_policy.index?,
      'contacts.create' => contact_policy.create?,
      'contacts.update' => contact_policy.update?,
      'contacts.delete' => contact_policy.destroy?,
      'contacts.import' => contact_policy.import?,
      'contacts.export' => contact_policy.export?
    }
  end

  def domain_status(entries)
    entries.all? { |entry| entry[:status] == 'planned' } ? 'planned' : 'enforced'
  end
end
