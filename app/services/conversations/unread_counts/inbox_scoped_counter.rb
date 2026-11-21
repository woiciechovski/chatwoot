class Conversations::UnreadCounts::InboxScopedCounter
  attr_reader :account, :user

  def self.applies_to?(account:, user:, account_user:)
    return false unless account_user&.agent?

    user.inboxes.exists?(
      account_id: account.id,
      agent_conversation_access: 'assigned_participating_or_team'
    )
  end

  def self.perform_if_applicable(account:, user:, account_user:)
    return unless applies_to?(account: account, user: user, account_user: account_user)

    new(account: account, user: user).perform
  end

  def initialize(account:, user:)
    @account = account
    @user = user
  end

  def perform
    conversations = visible_unread_conversations
    inbox_counts = conversations.group(:inbox_id).count
    team_counts = conversations
                  .where(team_id: user.teams.where(account_id: account.id).select(:id))
                  .group(:team_id)
                  .count

    {
      all_count: inbox_counts.values.sum,
      inboxes: stringify_counts(inbox_counts),
      labels: label_counts(conversations),
      teams: stringify_counts(team_counts)
    }
  end

  private

  def visible_unread_conversations
    conversations = account.conversations.open
                           .joins(:messages)
                           .merge(Message.incoming.reorder(nil))
                           .where(messages: { account_id: account.id })
                           .where(unread_since_last_seen_condition)
                           .distinct

    Conversations::PermissionFilterService.new(
      conversations,
      user,
      account,
      restricted_agent_inbox_access: true
    ).perform
  end

  def unread_since_last_seen_condition
    conversations = Conversation.arel_table
    messages = Message.arel_table

    conversations[:agent_last_seen_at].eq(nil).or(messages[:created_at].gt(conversations[:agent_last_seen_at]))
  end

  def stringify_counts(counts)
    counts.each_with_object({}) do |(id, count), result|
      result[id.to_s] = count if count.positive?
    end
  end

  def label_counts(conversations)
    labels = account.labels.where(show_on_sidebar: true).pluck(:title, :id)
    return {} if labels.empty?

    tag_counts = grouped_label_counts(conversations, labels)
    label_ids_by_title = labels.to_h

    tag_counts.each_with_object({}) do |(title, count), result|
      result[label_ids_by_title.fetch(title).to_s] = count if count.positive?
    end
  end

  def grouped_label_counts(conversations, labels)
    taggings = ActsAsTaggableOn::Tagging.arel_table
    tags = ActsAsTaggableOn::Tag.arel_table
    ActsAsTaggableOn::Tagging.joins(:tag)
                             .where(taggable_type: Conversation.polymorphic_name, context: 'labels')
                             .where(taggable_id: conversations.select(:id))
                             .where(tags[:name].in(labels.map(&:first)))
                             .group(tags[:name])
                             .distinct
                             .count(taggings[:taggable_id])
  end
end
