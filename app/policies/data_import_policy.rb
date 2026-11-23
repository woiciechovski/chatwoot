class DataImportPolicy < ApplicationPolicy
  def index?
    valid_account_membership? && (@account_user.administrator? || managed_contact_import?)
  end

  def show?
    return false unless valid_account_membership?
    return @account_user.administrator? && record.account_id == account.id if @account_user.administrator?

    managed_contact_import? && record.account_id == account.id && record.initiated_by_id == @account_user.user_id &&
      contacts_only_import?
  end

  def create?
    return false unless valid_account_membership?
    return true if @account_user.administrator?

    managed_contact_import? && contacts_only_import?
  end

  def validate_source?
    create?
  end

  def start?
    show?
  end

  def retry_import?
    show?
  end

  def abandon?
    show?
  end

  def skip_logs?
    show?
  end

  def error_logs?
    show?
  end

  def process_contacts?
    return false unless valid_account_membership?
    return true if @account_user.administrator? && record.account_id == account.id

    managed_contact_import? && record.account_id == account.id && contacts_only_import?
  end

  class Scope < Scope
    def resolve
      return scope.where(account_id: account.id) if account_user&.administrator?
      return scope.none unless account_user&.rbac_managed? && contacts_import_allowed?

      imports = scope.where(data_type: DataImport::INTEGRATION_DATA_TYPES, import_types: ['contacts'])
                     .or(scope.where(data_type: 'contacts', source_provider: nil))
      imports.where(account_id: account.id, initiated_by_id: account_user.user_id)
    end

    private

    def contacts_import_allowed?
      ContactPolicy.new(user_context, Contact).import?
    end
  end

  private

  def managed_contact_import?
    valid_account_membership? && @account_user.rbac_managed? && contact_import_allowed?
  end

  def contact_import_allowed?
    ContactPolicy.new(user_context, Contact).import?
  end

  def contacts_only_import?
    return true if record.legacy_contacts_csv_import?

    record.integration_import? && record.import_types == ['contacts']
  end

  def valid_account_membership?
    @account_user.is_a?(AccountUser) && @account_user.persisted? && account.present? && @account_user.account_id == account.id
  end
end
