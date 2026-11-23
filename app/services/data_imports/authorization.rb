class DataImports::Authorization
  def initialize(data_import)
    @data_import = data_import
  end

  def allowed_to_run?
    data_import = @data_import.reload
    account_user = AccountUser.find_by(account_id: data_import.account_id, user_id: data_import.initiated_by_id)
    return false unless account_user

    context = { user: account_user.user, account: data_import.account, account_user: account_user }
    DataImportPolicy.new(context, data_import).process_contacts?
  end
end
