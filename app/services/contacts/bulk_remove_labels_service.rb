class Contacts::BulkRemoveLabelsService
  def initialize(account:, contact_ids:, labels:, authorization: nil)
    @account = account
    @contact_ids = Array(contact_ids)
    @labels = Array(labels).compact_blank
    @authorization = authorization
  end

  def perform
    return { success: true, updated_contact_ids: [] } if @contact_ids.blank? || @labels.blank?

    updated_ids = []
    contacts.in_batches(of: 100) do |batch|
      return denied_result(updated_ids) unless authorized?

      batch.each do |contact|
        contact.update!(label_list: contact.label_list - @labels)
        updated_ids << contact.id
      end
    end

    { success: true, updated_contact_ids: updated_ids }
  end

  private

  def contacts
    @account.contacts.where(id: @contact_ids)
  end

  def authorized?
    @authorization&.allowed?('contacts.update')
  end

  def denied_result(updated_ids)
    { success: false, error: 'authorization_revoked', updated_contact_ids: updated_ids }
  end
end
