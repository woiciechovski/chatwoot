class Contacts::Authorization
  POLICY_ACTIONS = {
    'contacts.read' => :index?,
    'contacts.create' => :create?,
    'contacts.update' => :update?,
    'contacts.delete' => :destroy?,
    'contacts.import' => :import?,
    'contacts.export' => :export?
  }.freeze

  SYSTEM_AVATAR_ORIGINS = %w[
    contact_gravatar_callback
    contact_identify_action
    contact_inbox_with_contact_builder
    instagram_webhook
    telegram_update
    twitter_webhook
  ].freeze

  def self.allowed?(account:, user_id:, permission:, resource: nil)
    new(account: account, user_id: user_id).allowed?(permission, resource: resource)
  end

  def initialize(account:, user_id:)
    @account = account
    @user_id = user_id
  end

  def allowed?(permission, resource: nil)
    action = POLICY_ACTIONS.fetch(permission)
    account_user = @account.account_users.find_by(user_id: @user_id)
    return false unless account_user

    context = { user: account_user.user, account: @account, account_user: account_user }
    ContactPolicy.new(context, resource || Contact).public_send(action)
  end

  def avatar_allowed?(contact, authorization)
    authorization = authorization.to_h.with_indifferent_access
    return false unless contact.account_id == @account.id
    return false unless authorization[:account_id].to_i == @account.id
    return false unless authorization[:principal_contact_id].to_i == contact.id

    if authorization[:user_id].present?
      return false unless %w[contacts.create contacts.update].include?(authorization[:permission])

      return allowed?(authorization[:permission], resource: contact)
    end

    system_avatar_allowed?(contact, authorization)
  end

  def self.user_avatar_context(account_user:, contact:, permission:)
    {
      account_id: account_user.account_id,
      user_id: account_user.user_id,
      permission: permission,
      principal_contact_id: contact.id
    }
  end

  def self.system_avatar_context(contact:, inbox:, origin:)
    {
      account_id: contact.account_id,
      system_origin: origin,
      principal_contact_id: contact.id,
      inbox_id: inbox.id
    }
  end

  private

  def system_avatar_allowed?(contact, authorization)
    return false unless SYSTEM_AVATAR_ORIGINS.include?(authorization[:system_origin])
    return false if authorization[:inbox_id].blank?

    ContactInbox.joins(:inbox).exists?(
      contact_id: contact.id,
      inbox_id: authorization[:inbox_id],
      inboxes: { account_id: @account.id }
    )
  end
end
