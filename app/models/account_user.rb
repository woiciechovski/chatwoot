# == Schema Information
#
# Table name: account_users
#
#  id                       :bigint           not null, primary key
#  accepts_calls            :boolean          default(TRUE), not null
#  accepts_conversations    :boolean          default(TRUE), not null
#  active_at                :datetime
#  auto_offline             :boolean          default(TRUE), not null
#  availability             :integer          default("online"), not null
#  role                     :integer          default("agent")
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  account_id               :bigint
#  agent_capacity_policy_id :bigint
#  custom_role_id           :bigint
#  inviter_id               :bigint
#  user_id                  :bigint
#
# Indexes
#
#  index_account_users_on_account_id                (account_id)
#  index_account_users_on_agent_capacity_policy_id  (agent_capacity_policy_id)
#  index_account_users_on_custom_role_id            (custom_role_id)
#  index_account_users_on_user_id                   (user_id)
#  uniq_user_id_per_account_id                      (account_id,user_id) UNIQUE
#

class AccountUser < ApplicationRecord
  include AvailabilityStatusable
  include AccountUserAdministratorProtection

  belongs_to :account
  belongs_to :user
  belongs_to :inviter, class_name: 'User', optional: true
  belongs_to :rbac_role, optional: true, inverse_of: :account_users

  enum role: { agent: 0, administrator: 1 }
  enum availability: { online: 0, offline: 1, busy: 2 }

  accepts_nested_attributes_for :account

  before_validation :mark_rbac_managed_when_role_is_assigned
  before_validation :lock_membership_security_state, if: :requires_membership_lock?
  before_destroy :lock_membership_for_destruction, prepend: true
  before_destroy :prevent_removing_last_administrator
  after_create_commit :notify_creation, :create_notification_setting
  after_destroy :notify_deletion, :remove_user_from_account
  after_save :update_presence_in_redis, if: :saved_change_to_availability?
  after_commit :invalidate_filtered_unread_count_visibility, on: [:create, :destroy]
  after_update_commit :invalidate_filtered_unread_count_visibility_update, if: :filtered_unread_count_visibility_changed?

  validates :user_id, uniqueness: { scope: :account_id }
  validate :accepts_conversations_or_calls
  validate :rbac_role_belongs_to_account
  validate :rbac_role_is_for_an_agent
  validate :rbac_role_is_active, if: :assigning_rbac_role?
  validate :rbac_role_is_exclusive_with_enterprise_role
  validate :rbac_managed_cannot_return_to_legacy
  validate :account_keeps_an_administrator, if: :demoting_last_administrator?

  def create_notification_setting
    setting = user.notification_settings.new(account_id: account.id)
    setting.selected_email_flags = [:email_conversation_assignment]
    setting.selected_push_flags = [:push_conversation_assignment]
    setting.save!
  end

  def remove_user_from_account
    parent_account = Account.find_by(id: account_id)
    parent_user = User.find_by(id: user_id)
    return if parent_account.blank? || parent_user.blank?

    ::Agents::DestroyJob.perform_later(parent_account, parent_user)
  end

  def permissions
    administrator? ? ['administrator'] : ['agent']
  end

  def push_event_data
    {
      id: id,
      availability: availability,
      role: role,
      user_id: user_id
    }
  end

  private

  def notify_creation
    Rails.configuration.dispatcher.dispatch(AGENT_ADDED, Time.zone.now, account: account)
  end

  def notify_deletion
    parent_account = Account.find_by(id: account_id)
    return unless parent_account

    Rails.configuration.dispatcher.dispatch(AGENT_REMOVED, Time.zone.now, account: parent_account)
  end

  def update_presence_in_redis
    OnlineStatusTracker.set_status(account.id, user.id, availability)
  end

  def filtered_unread_count_visibility_changed?
    previous_changes.key?('role') || previous_changes.key?('custom_role_id')
  end

  def invalidate_filtered_unread_count_visibility
    parent_account = Account.find_by(id: account_id)
    return unless parent_account

    ::Conversations::UnreadCounts::FilteredCountInvalidator.new(parent_account).user_visibility_changed!(user_id: user_id)
  end

  def invalidate_filtered_unread_count_visibility_update
    dispatch_account_cache_invalidated if invalidate_filtered_unread_count_visibility
  end

  def dispatch_account_cache_invalidated
    Rails.configuration.dispatcher.dispatch(ACCOUNT_CACHE_INVALIDATED, Time.zone.now, account: account, cache_keys: account.cache_keys)
  end

  def accepts_conversations_or_calls
    return if accepts_conversations || accepts_calls

    errors.add(:base, I18n.t('errors.account_user.no_work_preference'))
  end

  def mark_rbac_managed_when_role_is_assigned
    self.rbac_managed = true if rbac_role_id.present?
  end

  def rbac_role_belongs_to_account
    return if rbac_role.blank? || rbac_role.account_id == account_id

    errors.add(:rbac_role, I18n.t('errors.account_user.rbac_role_account_mismatch'))
  end

  def rbac_role_is_for_an_agent
    return if role_state_value(:rbac_role_id).blank? || agent?

    errors.add(:rbac_role, I18n.t('errors.account_user.rbac_role_agent_only'))
  end

  def rbac_role_is_active
    return if rbac_role.blank? || rbac_role.active?

    errors.add(:rbac_role, I18n.t('errors.account_user.rbac_role_inactive'))
  end

  def assigning_rbac_role?
    rbac_role_id.present? && (new_record? || will_save_change_to_rbac_role_id?)
  end

  def rbac_role_is_exclusive_with_enterprise_role
    custom_role_id = role_state_value(:custom_role_id)
    rbac_role_id = role_state_value(:rbac_role_id)
    rbac_managed = role_state_value(:rbac_managed)
    return if custom_role_id.blank? || (rbac_role_id.blank? && !rbac_managed)

    errors.add(:rbac_role, I18n.t('errors.account_user.rbac_role_enterprise_conflict'))
  end

  def rbac_managed_cannot_return_to_legacy
    return unless will_save_change_to_rbac_managed?
    return unless persisted_role_state_value(:rbac_managed) && !rbac_managed?

    errors.add(:rbac_managed, I18n.t('errors.account_user.rbac_managed_cannot_revert'))
  end

  def demoting_last_administrator?
    persisted? && persisted_role_state_value(:role) == 'administrator' && !administrator?
  end

  def becoming_administrator?
    administrator? && account_id.present? && (new_record? || persisted_role_state_value(:role) != 'administrator')
  end

  def requires_membership_lock?
    new_record? || (
      will_save_change_to_account_id? || will_save_change_to_user_id? ||
      will_save_change_to_role? || will_save_change_to_rbac_role_id? ||
        will_save_change_to_rbac_managed? || will_save_change_to_custom_role_id?
    )
  end

  def lock_membership_security_state
    lock_membership_with_existing_parents
  end

  def lock_membership_for_destruction
    lock_membership_with_existing_parents(allow_missing_parents: true)
  end

  def lock_membership_with_existing_parents(allow_missing_parents: false)
    return if account_id.blank? || user_id.blank?

    membership_id = id if persisted?
    Rbac::MembershipLockService.with_membership(
      account_id: account_id,
      user_id: user_id,
      membership_id: membership_id,
      allow_missing_account: allow_missing_parents,
      allow_missing_user: allow_missing_parents
    ) do |locked_account, _locked_user, locked_membership|
      @locked_account = locked_account
      capture_persisted_role_state(locked_membership) if locked_membership
    end
  end

  def capture_persisted_role_state(membership)
    @persisted_role_state = {
      role: membership.attribute_in_database('role'),
      rbac_role_id: membership.attribute_in_database('rbac_role_id'),
      rbac_managed: membership.attribute_in_database('rbac_managed'),
      custom_role_id: membership.attribute_in_database('custom_role_id')
    }
  end

  def role_state_value(attribute)
    return public_send(attribute) if will_save_change_to_attribute?(attribute)

    persisted_role_state_value(attribute)
  end

  def persisted_role_state_value(attribute)
    return @persisted_role_state.fetch(attribute) if @persisted_role_state

    attribute_in_database(attribute.to_s)
  end
end

AccountUser.prepend_mod_with('AccountUser')
AccountUser.include_mod_with('Audit::AccountUser')
AccountUser.include_mod_with('Concerns::AccountUser')
