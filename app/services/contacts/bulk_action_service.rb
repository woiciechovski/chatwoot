class Contacts::BulkActionService
  def initialize(account:, user:, params:)
    @account = account
    @user = user
    @params = params.deep_symbolize_keys
  end

  def perform
    permission = permission_for_operation
    return unknown_operation if permission.blank?
    return denied_operation unless authorization.allowed?(permission)

    return delete_contacts if delete_requested?
    return assign_labels if labels_to_add.any?
    return remove_labels if labels_to_remove.any?

    unknown_operation
  end

  private

  def unknown_operation
    Rails.logger.warn("Unknown contact bulk operation payload: #{@params.keys}")
    { success: false, error: 'unknown_operation' }
  end

  def denied_operation
    Rails.logger.warn("Denied contact bulk operation for user #{@user.id} in account #{@account.id}")
    { success: false, error: 'authorization_denied' }
  end

  def permission_for_operation
    return 'contacts.delete' if delete_requested?
    return 'contacts.update' if labels_to_add.any? || labels_to_remove.any?
  end

  def authorization
    @authorization ||= Contacts::Authorization.new(account: @account, user_id: @user.id)
  end

  def assign_labels
    Contacts::BulkAssignLabelsService.new(
      account: @account,
      contact_ids: ids,
      labels: labels_to_add,
      authorization: authorization
    ).perform
  end

  def remove_labels
    Contacts::BulkRemoveLabelsService.new(
      account: @account,
      contact_ids: ids,
      labels: labels_to_remove,
      authorization: authorization
    ).perform
  end

  def delete_contacts
    Contacts::BulkDeleteService.new(
      account: @account,
      contact_ids: ids,
      authorization: authorization
    ).perform
  end

  def ids
    Array(@params[:ids]).compact
  end

  def labels_to_add
    @labels_to_add ||= Array(@params.dig(:labels, :add)).reject(&:blank?)
  end

  def labels_to_remove
    @labels_to_remove ||= Array(@params.dig(:labels, :remove)).reject(&:blank?)
  end

  def delete_requested?
    @params[:action_name] == 'delete'
  end
end
