class ConversationFlowExecution < ApplicationRecord
  PROTECTED_STATUSES = %w[reserved transferring failed].freeze

  belongs_to :account
  belongs_to :conversation_flow, inverse_of: :executions
  belongs_to :conversation, inverse_of: :conversation_flow_execution
  belongs_to :transferred_by, class_name: 'User', optional: true
  belongs_to :team, optional: true

  enum :status, { reserved: 'reserved', transferring: 'transferring', completed: 'completed', failed: 'failed' }

  validates :conversation_id, uniqueness: true
  validates :reserved_at, presence: true
  validate :validate_conversation_account
  validate :validate_flow_account
  validate :validate_team_account
  validate :validate_transfer_actor_account

  scope :in_triage, -> { where(status: PROTECTED_STATUSES) }

  def protected?
    PROTECTED_STATUSES.include?(status)
  end

  private

  def validate_conversation_account
    validate_association_account(:conversation, conversation)
  end

  def validate_flow_account
    validate_association_account(:conversation_flow, conversation_flow)
  end

  def validate_team_account
    validate_association_account(:team, team)
  end

  def validate_transfer_actor_account
    return if transferred_by.blank? || account&.users&.exists?(id: transferred_by_id)

    errors.add(:transferred_by, :invalid)
  end

  def validate_association_account(association_name, record)
    return if record.blank? || record.account_id == account_id

    errors.add(association_name, :invalid)
  end
end
