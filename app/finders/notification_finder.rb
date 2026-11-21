class NotificationFinder
  attr_reader :current_user, :current_account, :params

  RESULTS_PER_PAGE = 15

  def initialize(current_user, current_account, params = {})
    @current_user = current_user
    @current_account = current_account
    @params = params
    set_up
  end

  def notifications
    @notifications.page(current_page).per(RESULTS_PER_PAGE).order(last_activity_at: sort_order)
  end

  def unread_count
    if type_included?('read')
      # If we're including read notifications, filter to unread
      @notifications.where(read_at: nil).count
    else
      # Already filtered to unread notifications, just count
      @notifications.count
    end
  end

  def count
    @notifications.count
  end

  private

  def set_up
    find_all_notifications
    filter_snoozed_notifications
    filter_read_notifications
  end

  def find_all_notifications
    @notifications = current_user.notifications.where(account_id: @current_account.id)
    return if current_user.account_users.exists?(account_id: @current_account.id, role: :administrator)

    notification_table = Notification.arel_table
    reserved_conversation_ids = ConversationFlowExecution.in_triage.select(:conversation_id).arel
    visible_actor = notification_table[:primary_actor_type].not_eq('Conversation')
    visible_actor = visible_actor.or(notification_table[:primary_actor_id].not_in(reserved_conversation_ids))
    @notifications = @notifications.where(visible_actor)
    filter_inaccessible_restricted_conversation_notifications
  end

  def filter_inaccessible_restricted_conversation_notifications
    restricted_inbox_ids = current_user.inboxes.where(
      account_id: current_account.id,
      agent_conversation_access: 'assigned_participating_or_team'
    ).select(:id)
    return unless restricted_inbox_ids.exists?

    restricted_conversations = current_account.conversations.where(inbox_id: restricted_inbox_ids)
    visible_conversation_ids = Conversations::PermissionFilterService.new(
      restricted_conversations,
      current_user,
      current_account
    ).perform.select(:id)
    inaccessible_notifications = @notifications.where(
      primary_actor_type: 'Conversation',
      primary_actor_id: restricted_conversations.select(:id)
    ).where.not(primary_actor_id: visible_conversation_ids)

    @notifications = @notifications.where.not(id: inaccessible_notifications.select(:id))
  end

  def filter_snoozed_notifications
    @notifications = @notifications.where(snoozed_until: nil) unless type_included?('snoozed')
  end

  def filter_read_notifications
    @notifications = @notifications.where(read_at: nil) unless type_included?('read')
  end

  def type_included?(type)
    (params[:includes] || []).include?(type)
  end

  def current_page
    params[:page] || 1
  end

  def sort_order
    params[:sort_order] || :desc
  end
end
