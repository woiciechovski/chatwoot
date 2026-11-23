class RbacAuditEvent < ApplicationRecord
  belongs_to :account
  belongs_to :actor, polymorphic: true, optional: true

  validates :action, :target_type, presence: true
  validates :result, inclusion: { in: %w[success denied failure] }
  validate :details_are_an_object

  private

  def details_are_an_object
    return if details.is_a?(Hash)

    errors.add(:details, :invalid)
  end
end
