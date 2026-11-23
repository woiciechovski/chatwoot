class ContactPolicy < ApplicationPolicy
  def index?
    contacts_permission?('contacts.read') { true }
  end

  def active?
    contacts_permission?('contacts.read') { true }
  end

  def import?
    contacts_permission?('contacts.import') { @account_user.administrator? }
  end

  def export?
    contacts_permissions?(%w[contacts.read contacts.export]) { @account_user.administrator? }
  end

  def search?
    contacts_permission?('contacts.read') { true }
  end

  def filter?
    contacts_permission?('contacts.read') { true }
  end

  def update?
    contacts_permission?('contacts.update') { true }
  end

  def contactable_inboxes?
    contacts_permission?('contacts.read') { true }
  end

  def destroy_custom_attributes?
    contacts_permission?('contacts.update') { true }
  end

  def show?
    contacts_permission?('contacts.read') { true }
  end

  def create?
    contacts_permission?('contacts.create') { true }
  end

  def avatar?
    contacts_permission?('contacts.update') { true }
  end

  def destroy?
    contacts_permission?('contacts.delete') { @account_user.administrator? }
  end

  def merge?
    contacts_permissions?(%w[contacts.read contacts.update contacts.delete]) { true }
  end

  private

  def contacts_permission?(permission)
    return false unless valid_account_context?
    if @account_user.rbac_managed?
      return Rbac::Authorizer.allowed?(account_user: @account_user, permission: permission, resource: authorization_resource)
    end

    yield
  end

  def contacts_permissions?(permissions)
    return false unless valid_account_context?
    return yield unless @account_user.rbac_managed?

    permissions.all? do |permission|
      Rbac::Authorizer.allowed?(account_user: @account_user, permission: permission, resource: authorization_resource)
    end
  end

  def valid_account_context?
    return false unless @account_user.is_a?(AccountUser) && @account_user.persisted?
    return false unless @account.present? && @account_user.account_id == @account.id
    return false if authorization_resource && authorization_resource.account_id != @account_user.account_id

    true
  end

  def authorization_resource
    @record if @record.is_a?(Contact)
  end
end

ContactPolicy.prepend_mod_with('ContactPolicy')
