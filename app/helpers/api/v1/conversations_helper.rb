module Api::V1::ConversationsHelper
  def contact_history_message_data(message, conversation)
    data = message&.push_event_data
    return data unless data && contact_history_request?

    secure_contact_history_attachments(data, message, conversation)
    data
  end

  private

  def contact_history_request?
    controller.controller_path == 'api/v1/accounts/contacts/conversations'
  end

  def secure_contact_history_attachments(data, message, conversation)
    attachments_by_id = message.attachments.index_by(&:id)
    data[:attachments]&.each do |attachment_data|
      secure_contact_history_attachment(attachment_data, attachments_by_id, conversation)
    end
  end

  def secure_contact_history_attachment(attachment_data, attachments_by_id, conversation)
    attachment = attachments_by_id[attachment_data[:id]]
    download_path = attachment_download_path(attachment, conversation)
    attachment_data[:data_url] = download_path || ''
    attachment_data[:thumb_url] = attachment_thumbnail_path(attachment, download_path)
  end

  def attachment_download_path(attachment, conversation)
    return unless attachment&.file&.attached?

    api_v1_account_contact_attachment_download_path(
      account_id: Current.account.id,
      contact_id: conversation.contact_id,
      id: attachment.id
    )
  end

  def attachment_thumbnail_path(attachment, download_path)
    return '' unless download_path && attachment.image? && attachment.file.representable?

    "#{download_path}?thumbnail=true"
  end
end
