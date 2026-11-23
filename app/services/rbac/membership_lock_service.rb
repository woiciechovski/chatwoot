class Rbac::MembershipLockService
  class LockScopeExpansionError < StandardError; end

  class RetryLockAcquisition < StandardError; end

  LOCK_SCOPE_KEY = :rbac_membership_lock_scope

  class << self
    def with_account(account_id:, &)
      scope = current_scope
      return yield_account_from_scope(scope, account_id, &) if scope

      with_transaction do
        account = Account.lock.find(account_id)
        with_lock_scope(accounts: [account]) { yield account }
      end
    end

    def with_membership(account_id:, user_id:, membership_id: nil, allow_missing_account: false, allow_missing_user: false, &)
      scope = current_scope
      return yield_membership_from_scope(scope, account_id, user_id, membership_id, &) if scope

      with_transaction do
        account = Account.lock.find_by(id: account_id)
        raise ActiveRecord::RecordNotFound, "Couldn't find Account with 'id'=#{account_id}" if account.nil? && !allow_missing_account

        user = User.lock.find_by(id: user_id)
        raise ActiveRecord::RecordNotFound, "Couldn't find User with 'id'=#{user_id}" if user.nil? && !allow_missing_user

        membership = lock_membership(account_id, user_id, membership_id)

        with_lock_scope(
          accounts: [account].compact,
          account_ids: [account_id],
          users: [user].compact,
          memberships: [membership].compact
        ) do
          yield account, user, membership
        end
      end
    end

    def with_user_memberships(user_id:, &)
      scope = current_scope
      return yield_user_memberships_from_scope(scope, user_id, &) if scope

      with_user_memberships_attempt(user_id, &)
    rescue RetryLockAcquisition
      retry
    end

    private

    def with_transaction(&)
      ActiveRecord::Base.transaction(requires_new: true, &)
    end

    def current_scope
      scope = ActiveSupport::IsolatedExecutionState[LOCK_SCOPE_KEY]
      return unless scope
      return unless scope.fetch(:connection_id) == ActiveRecord::Base.connection.object_id

      scope
    end

    def with_lock_scope(accounts:, account_ids: accounts.map(&:id), users: [], memberships: [])
      previous_scope = ActiveSupport::IsolatedExecutionState[LOCK_SCOPE_KEY]
      scope = {
        connection_id: ActiveRecord::Base.connection.object_id,
        account_ids: account_ids,
        accounts_by_id: accounts.index_by(&:id),
        users_by_id: users.index_by(&:id),
        memberships_by_id: memberships.index_by(&:id),
        membership_phase_started: memberships.any? || users.any?
      }
      ActiveSupport::IsolatedExecutionState[LOCK_SCOPE_KEY] = scope
      yield
    ensure
      ActiveSupport::IsolatedExecutionState[LOCK_SCOPE_KEY] = previous_scope
    end

    def yield_account_from_scope(scope, account_id, &)
      account = scope[:accounts_by_id][account_id]
      raise LockScopeExpansionError unless account

      yield account
    end

    def yield_membership_from_scope(scope, account_id, user_id, membership_id, &)
      account = locked_account_from_scope(scope, account_id)
      user = locked_user_from_scope(scope, user_id)
      membership = locked_membership_from_scope(scope, account_id, user_id, membership_id)
      scope[:membership_phase_started] = true
      yield account, user, membership
    end

    def locked_account_from_scope(scope, account_id)
      raise LockScopeExpansionError unless scope[:account_ids].include?(account_id)

      scope[:accounts_by_id][account_id]
    end

    def locked_user_from_scope(scope, user_id)
      user = scope[:users_by_id][user_id]
      return user if user
      raise LockScopeExpansionError if scope[:users_by_id].any? || scope[:membership_phase_started]

      user = User.lock.find(user_id)
      scope[:users_by_id][user_id] = user
    end

    def locked_membership_from_scope(scope, account_id, user_id, membership_id)
      return unless membership_id

      membership = scope[:memberships_by_id][membership_id]
      if membership
        raise LockScopeExpansionError unless membership.account_id == account_id && membership.user_id == user_id

        return membership
      end
      raise LockScopeExpansionError if scope[:membership_phase_started]

      membership = lock_membership(account_id, user_id, membership_id)
      scope[:memberships_by_id][membership.id] = membership
    end

    def yield_user_memberships_from_scope(scope, user_id, &)
      user = scope[:users_by_id][user_id]
      raise LockScopeExpansionError unless user

      ensure_scope_covers_user_memberships!(scope, user_id)
      memberships = scope[:memberships_by_id].values.sort_by { |membership| [membership.account_id, membership.id] }
      yield scope[:accounts_by_id].values.sort_by(&:id), user, memberships
    end

    def ensure_scope_covers_user_memberships!(scope, user_id)
      linked_ids = linked_account_ids(user_id)
      locked_ids = scope[:account_ids]
      raise LockScopeExpansionError if (linked_ids - locked_ids).any?

      linked_membership_ids = AccountUser.where(user_id: user_id).order(:account_id, :id).pluck(:id)
      locked_membership_ids = scope[:memberships_by_id].keys.sort
      raise LockScopeExpansionError unless linked_membership_ids == locked_membership_ids
    end

    def with_user_memberships_attempt(user_id, &)
      ActiveRecord::Base.transaction(requires_new: true) do
        account_ids = linked_account_ids(user_id)
        accounts = lock_accounts(account_ids)
        user = User.lock.find(user_id)
        refreshed_account_ids = linked_account_ids(user_id)
        raise RetryLockAcquisition if (refreshed_account_ids - account_ids).any?

        memberships = lock_user_memberships(user_id)
        with_lock_scope(accounts: accounts, account_ids: account_ids, users: [user], memberships: memberships) do
          yield accounts, user, memberships
        end
      end
    end

    def lock_accounts(account_ids)
      ids = account_ids.uniq.sort
      return [] if ids.empty?

      Account.where(id: ids).order(:id).lock.to_a
    end

    def linked_account_ids(user_id)
      AccountUser.where(user_id: user_id).distinct.order(:account_id).pluck(:account_id)
    end

    def lock_user_memberships(user_id)
      AccountUser.where(user_id: user_id).order(:account_id, :id).lock.to_a
    end

    def lock_membership(account_id, user_id, membership_id)
      return unless membership_id

      AccountUser.lock.find_by!(id: membership_id, account_id: account_id, user_id: user_id)
    end
  end
end
