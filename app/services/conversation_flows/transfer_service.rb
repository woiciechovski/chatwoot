class ConversationFlows::TransferService
  class InvalidTeam < StandardError; end
  class AlreadyTransferred < StandardError; end

  pattr_initialize [:execution!, :team!, :user!]

  def perform
    validate_team!

    execution.with_lock do
      raise AlreadyTransferred unless execution.reserved? || execution.failed?

      transfer_locked_execution
    end

    execution
  rescue AlreadyTransferred, InvalidTeam
    raise
  rescue StandardError => e
    record_failure(e)
    raise
  ensure
    @conversation.flow_transfer_in_progress = false if @conversation
  end

  private

  def validate_team!
    return if team.present? && team.account_id == execution.account_id

    raise InvalidTeam, 'Team must belong to the execution account'
  end

  def transfer_locked_execution
    @conversation = execution.conversation
    @conversation.flow_transfer_in_progress = true

    execution.update!(status: :transferring, failure_message: nil, failed_at: nil)
    @conversation.update!(team: team)
    execution.update!(
      status: :completed,
      team: team,
      transferred_by: user,
      transferred_at: Time.current,
      failure_message: nil,
      failed_at: nil
    )
  end

  def record_failure(error)
    execution.reload
    return if execution.completed?

    execution.update!(status: :failed, failure_message: error.message, failed_at: Time.current)
  end
end
