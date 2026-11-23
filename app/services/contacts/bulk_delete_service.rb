class Contacts::BulkDeleteService
  def initialize(account:, contact_ids: [], authorization: nil)
    @account = account
    @contact_ids = Array(contact_ids).compact
    @authorization = authorization
  end

  def perform
    return { success: true, updated_contact_ids: [] } if @contact_ids.blank?

    deleted_ids = []
    contacts.in_batches(of: 100) do |batch|
      return denied_result(deleted_ids) unless authorized?

      batch.each do |contact|
        contact.destroy!
        deleted_ids << contact.id
      end
    end

    { success: true, updated_contact_ids: deleted_ids }
  end

  private

  def contacts
    @account.contacts.where(id: @contact_ids)
  end

  def authorized?
    @authorization&.allowed?('contacts.delete')
  end

  def denied_result(deleted_ids)
    { success: false, error: 'authorization_revoked', updated_contact_ids: deleted_ids }
  end
end
