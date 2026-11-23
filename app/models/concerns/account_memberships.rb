module AccountMemberships
  def agents
    users.where(account_users: { role: :agent })
  end

  def administrators
    users.where(account_users: { role: :administrator })
  end

  def usable_administrators
    return account_users.none unless active?

    account_users.administrator.joins(:user)
  end
end
