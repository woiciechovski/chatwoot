require 'rails_helper'

RSpec.describe AccountUser do
  self.use_transactional_tests = false

  # Concurrent database connections need committed shared setup records outside per-example transactions.
  # rubocop:disable RSpec/BeforeAfterAll, RSpec/InstanceVariable
  before(:all) do
    @account = create(:account)
    @linked_account_ids = []
    @administrators = create_list(:account_user, 2, account: @account, role: :administrator)
    @agent_membership = create(:account_user, account: @account, role: :agent)
    @memberships = @administrators + [@agent_membership]
    @rbac_role = RbacRole.create!(account: @account, name: 'Support')
  end

  after(:all) do
    account_ids = [@account.id, *@linked_account_ids]
    account_user_ids = described_class.where(account_id: account_ids).pluck(:id)
    user_ids = described_class.where(id: account_user_ids).pluck(:user_id)
    Audited::Audit.where(auditable_type: 'AccountUser', auditable_id: account_user_ids).delete_all
    Audited::Audit.where(associated_type: 'Account', associated_id: account_ids).delete_all
    described_class.where(id: account_user_ids).delete_all
    RbacRole.where(id: @rbac_role.id).delete_all
    NotificationSetting.where(user_id: user_ids).delete_all
    User.where(id: user_ids).delete_all
    Account.where(id: account_ids).delete_all
  end

  it 'serializes concurrent demotions so one administrator remains' do
    ready = Queue.new
    start = Queue.new
    administrator_ids = @administrators.map(&:id)
    threads = administrator_ids.map do |administrator_id|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          described_class.find(administrator_id).update(role: :agent)
        end
      end
    end

    2.times { ready.pop }
    2.times { start << true }
    threads.each(&:value)

    expect(described_class.where(account_id: @account.id, role: :administrator).count).to eq(1)
  end

  it 'does not promote a stale membership after a concurrent RBAC assignment' do
    loaded = Queue.new
    continue = Queue.new
    membership_id = @agent_membership.id
    promotion = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        stale_membership = described_class.find(membership_id)
        loaded << true
        continue.pop
        stale_membership.update(role: :administrator)
      end
    end

    loaded.pop
    actor = described_class.where(account_id: @account.id, role: :administrator).first!
    Rbac::RoleManagementService.new(account: @account, actor: actor).assign_role!(
      account_user_id: membership_id,
      role_id: @rbac_role.id
    )
    continue << true

    expect(promotion.value).to be(false)
    expect(described_class.find(membership_id)).to be_agent
    expect(described_class.find(membership_id).rbac_role_id).to eq(@rbac_role.id)
  end

  it 'restarts the full lock attempt when a new account link appears after discovery' do
    result = run_lock_retry_schedule(
      account_id: @account.id,
      user_id: @agent_membership.user_id
    )

    expect(result[:blocker_completed]).to be(true)
    expect(result[:account_ids]).to eq([@account.id, @linked_account_ids.last].sort)
    expect(result[:backend_pids].uniq.size).to eq(3)
    expect(result[:lock_tables]).to eq(%w[accounts users accounts users account_users])
  end

  it 'serializes promotion against global user deletion' do
    promotion_user = create(:user)
    promotion_membership = create(:account_user, account: @account, user: promotion_user, role: :agent)
    deletion_locked = Queue.new
    release_deletion = Queue.new
    promotion_started = Queue.new

    deletion = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Rbac::MembershipLockService.with_user_memberships(user_id: promotion_user.id) do |_accounts, locked_user, _memberships|
          deletion_locked << true
          release_deletion.pop
          locked_user.destroy
          [locked_user.destroyed?, locked_user.errors.full_messages]
        end
      end
    end

    deletion_locked.pop
    promotion = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        promotion_started << true
        described_class.find(promotion_membership.id).update(role: :administrator)
      end
    rescue ActiveRecord::RecordNotFound
      :user_deleted_first
    end

    promotion_started.pop
    release_deletion << true

    expect(deletion.value).to eq([true, []])
    expect(promotion.value).to eq(:user_deleted_first)
    expect(User.exists?(promotion_user.id)).to be(false)
    expect(@account.usable_administrators.count).to be >= 1
  ensure
    described_class.where(user_id: promotion_user&.id).delete_all
    User.where(id: promotion_user&.id).delete_all
  end

  it 'keeps every account usable when multi-account administrator removals race with deletion' do
    extra_accounts = create_list(:account, 2)
    target_user = create(:user)
    memberships = extra_accounts.map do |account|
      create(:account_user, account: account, user: target_user, role: :administrator)
    end
    extra_administrators = extra_accounts.map do |account|
      create(:account_user, account: account, role: :administrator)
    end
    start = Queue.new

    removals = memberships.map do |membership|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          start.pop
          membership.destroy!
        end
      end
    end
    deletion = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        start.pop
        target_user.destroy
      end
    end

    3.times { start << true }
    removals.each(&:value)
    deletion.value

    expect(extra_accounts.zip(extra_administrators).all? { |account, admin| account.usable_administrators.exists?(admin.id) }).to be(true)
    expect(described_class.where(id: memberships.map(&:id))).to be_empty

    target_user.reload.destroy! if User.exists?(target_user.id)
    expect(User.exists?(target_user.id)).to be(false)
  ensure
    cleanup_concurrency_records(accounts: extra_accounts || [], users: [target_user].compact)
  end

  it 'lets deletion win before AccountBuilder can link the user to another account' do
    target_user = create(:user)
    create(:account_user, account: @account, user: target_user, role: :agent)
    account_name = "Concurrent account #{SecureRandom.hex(6)}"
    deletion_locked = Queue.new
    release_deletion = Queue.new
    builder_started = Queue.new

    deletion = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Rbac::MembershipLockService.with_user_memberships(user_id: target_user.id) do |_accounts, locked_user, _memberships|
          deletion_locked << true
          release_deletion.pop
          locked_user.destroy
          [locked_user.destroyed?, locked_user.errors.full_messages]
        end
      end
    end

    deletion_locked.pop
    builder = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        builder_started << true
        AccountBuilder.new(account_name: account_name, email: target_user.email, user: User.find(target_user.id)).perform
      end
    rescue ActiveRecord::RecordNotFound
      :user_deleted_first
    end

    builder_started.pop
    release_deletion << true

    expect(deletion.value).to eq([true, []])
    expect(builder.value).to eq(:user_deleted_first)
    expect(User.exists?(target_user.id)).to be(false)
    expect(Account.where(name: account_name)).to be_empty
  ensure
    account_ids = Account.where(name: account_name).pluck(:id)
    described_class.where(account_id: account_ids).delete_all
    Account.where(id: account_ids).delete_all
    described_class.where(user_id: target_user&.id).delete_all
    User.where(id: target_user&.id).delete_all
  end

  it 'rejects one of two concurrent role edits that use the same version' do
    role = RbacRole.create!(account: @account, name: 'Concurrent role edit')
    editor_membership = create(:account_user, account: @account, role: :administrator)
    ready = Queue.new
    start = Queue.new
    backend_pids = Queue.new
    editors = %w[First Second]

    threads = editors.map do |editor|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          backend_pids << ActiveRecord::Base.connection.raw_connection.backend_pid
          ready << true
          start.pop
          actor = described_class.find(editor_membership.id)
          service = Rbac::RoleManagementService.new(account: Account.find(@account.id), actor: actor)
          service.update_role!(role_id: role.id, attributes: { name: "Concurrent #{editor}" }, expected_version: 0)
          :updated
        rescue Rbac::RoleManagementService::StaleVersionError
          :stale
        end
      end
    end

    2.times { ready.pop }
    2.times { start << true }
    outcomes = threads.map(&:value)
    pids = Array.new(2) { backend_pids.pop }

    expect(outcomes).to contain_exactly(:updated, :stale)
    expect(pids.uniq.size).to eq(2)
    expect(role.reload.lock_version).to eq(1)
    expect(RbacAuditEvent.where(account_id: @account.id, action: 'role.updated').count).to eq(1)
  ensure
    RbacAuditEvent.where(account_id: @account.id, action: 'role.updated').delete_all
    RbacRolePermission.where(rbac_role_id: role&.id).delete_all
    RbacRole.where(id: role&.id).delete_all
    described_class.where(id: editor_membership&.id).delete_all
    NotificationSetting.where(user_id: editor_membership&.user_id).delete_all
    User.where(id: editor_membership&.user_id).delete_all
  end

  def run_lock_retry_schedule(account_id:, user_id:)
    state = lock_retry_state
    subscription = subscribe_to_lock_retry_queries(state)
    lock_service = Rbac::MembershipLockService
    blocker = start_account_lock_blocker(state, account_id)
    reader = start_membership_reader(state, lock_service, user_id)
    wait_for_link_discovery(state, reader)
    creator = start_link_creator(state, user_id)
    linked_account_id = creator.value
    @linked_account_ids << linked_account_id
    state[:release_account_lock] << true
    collect_lock_retry_results(state, blocker, reader)
  ensure
    release_and_stop_lock_retry_threads(state)
    ActiveSupport::Notifications.unsubscribe(subscription) if subscription
  end

  def lock_retry_state
    {
      discovery_complete: Queue.new,
      worker_errors: Queue.new,
      lock_tables: Queue.new,
      backend_pids: Queue.new,
      account_lock_acquired: Queue.new,
      release_account_lock: Queue.new,
      threads: {}
    }
  end

  def subscribe_to_lock_retry_queries(state)
    ActiveSupport::Notifications.subscribe('sql.active_record') do |_name, _start, _finish, _id, payload|
      next unless Thread.current[:membership_lock_retry_test]

      record_lock_retry_query(state, payload[:sql])
    end
  end

  def record_lock_retry_query(state, sql)
    record_membership_discovery(state, sql)
    return unless sql.match?(/FOR UPDATE/i)

    state[:lock_tables] << sql.match(/FROM\s+"([^\"]+)"/i)&.captures&.first
  end

  def record_membership_discovery(state, sql)
    return unless sql.match?(/SELECT/i) && sql.include?('account_users') && sql.include?('account_id')

    state[:discovery_complete] << true
  end

  def start_account_lock_blocker(state, account_id)
    state[:threads][:blocker] = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        state[:backend_pids] << ActiveRecord::Base.connection.raw_connection.backend_pid
        Account.find(account_id).with_lock do
          state[:account_lock_acquired] << true
          state[:release_account_lock].pop
        end
      end
    end
    state[:account_lock_acquired].pop
    state[:threads][:blocker]
  end

  def start_membership_reader(state, lock_service, user_id)
    state[:threads][:reader] = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        state[:backend_pids] << ActiveRecord::Base.connection.raw_connection.backend_pid
        Thread.current[:membership_lock_retry_test] = true
        lock_service.with_user_memberships(user_id: user_id) do |accounts, _user, _memberships|
          accounts.map(&:id)
        end
      end
    rescue StandardError => e
      state[:worker_errors] << e
      raise
    end
  end

  def wait_for_link_discovery(state, reader)
    Timeout.timeout(10) { state[:discovery_complete].pop }
  rescue Timeout::Error
    raise state[:worker_errors].pop unless state[:worker_errors].empty?

    raise "link discovery timed out; reader stack: #{reader.backtrace&.first(10)}"
  end

  def start_link_creator(state, user_id)
    state[:threads][:creator] = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        state[:backend_pids] << ActiveRecord::Base.connection.raw_connection.backend_pid
        user = User.find(user_id)
        _linked_user, account = AccountBuilder.new(account_name: 'Late membership account', email: user.email, user: user).perform
        account.id
      end
    end
  end

  def collect_lock_retry_results(state, blocker, reader)
    blocker_completed = blocker.value
    account_ids = reader.value
    lock_tables = []
    lock_tables << state[:lock_tables].pop(true) until state[:lock_tables].empty?
    {
      blocker_completed: blocker_completed,
      account_ids: account_ids,
      backend_pids: Array.new(3) { state[:backend_pids].pop },
      lock_tables: lock_tables
    }
  end

  def release_and_stop_lock_retry_threads(state)
    threads = state&.fetch(:threads, {})&.values || []
    release_account_lock_if_needed(state, threads)
    stop_lock_retry_threads(threads)
  end

  def release_account_lock_if_needed(state, threads)
    state[:release_account_lock] << true if threads.any?(&:alive?)
  end

  def stop_lock_retry_threads(threads)
    threads.each { |thread| thread.kill if thread.alive? }
  end

  def cleanup_concurrency_records(accounts:, users:)
    account_ids = accounts.map(&:id)
    user_ids = users.map(&:id)
    membership_ids = AccountUser.where(account_id: account_ids, user_id: user_ids).pluck(:id)
    Audited::Audit.where(auditable_type: 'AccountUser', auditable_id: membership_ids).delete_all
    Audited::Audit.where(associated_type: 'Account', associated_id: account_ids).delete_all
    AccountUser.where(id: membership_ids).delete_all
    User.where(id: user_ids).delete_all
    Account.where(id: account_ids).delete_all
  end
  # rubocop:enable RSpec/BeforeAfterAll, RSpec/InstanceVariable
end
