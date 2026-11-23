module AccountUserAdministratorProtection
  extend ActiveSupport::Concern

  private

  def account_keeps_an_administrator
    parent_account = active_account
    return if parent_account.blank? || parent_account.suspended?

    has_another_administrator = parent_account.usable_administrators.where.not(id: id).exists?
    return if has_another_administrator

    errors.add(:role, :last_administrator, message: I18n.t('errors.account_user.last_administrator'))
  end

  def prevent_removing_last_administrator
    return true unless persisted_role_state_value(:role) == 'administrator'

    parent_account = active_account
    return true if parent_account.blank? || parent_account.suspended?

    has_another_administrator = parent_account.usable_administrators.where.not(id: id).exists?
    return true if has_another_administrator

    errors.add(:base, :last_administrator, message: I18n.t('errors.account_user.last_administrator'))
    throw :abort
  end

  def active_account
    return @locked_account if @locked_account&.id == account_id

    Account.find_by(id: account_id)
  end
end
