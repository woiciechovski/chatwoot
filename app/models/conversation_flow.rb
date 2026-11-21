class ConversationFlow < ApplicationRecord
  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :updated_by, class_name: 'User', optional: true

  has_many :inboxes, dependent: :nullify, inverse_of: :conversation_flow
  has_many :executions,
           class_name: 'ConversationFlowExecution',
           dependent: :restrict_with_error,
           inverse_of: :conversation_flow

  validates :name, presence: true
  validate :validate_creator_account, on: :create
  validate :validate_updater_account

  scope :enabled, -> { where(enabled: true) }

  private

  def validate_creator_account
    return if account&.account_users&.exists?(user_id: created_by_id, role: :administrator)

    errors.add(:created_by, :invalid)
  end

  def validate_updater_account
    return if updated_by.blank? || account&.users&.exists?(id: updated_by_id)

    errors.add(:updated_by, :invalid)
  end
end
