class Api::V1::Accounts::Contacts::AttachmentsController < Api::V1::Accounts::Contacts::BaseController
  include Contacts::AuthenticatedBlobDownloads

  RESULTS_PER_PAGE = 100

  before_action :authorize_contact_read!, only: [:index, :download]

  def index
    conversations = Conversations::PermissionFilterService.new(
      Current.account.conversations.where(contact_id: @contact.id),
      Current.user,
      Current.account
    ).perform

    @attachments = Attachment.where(message_id: Message.where(conversation_id: conversations).select(:id))
                             .includes({ file_attachment: :blob }, message: [:conversation, :inbox, { sender: { avatar_attachment: :blob } }])
                             .order(created_at: :desc)
                             .page(params[:page])
                             .per(RESULTS_PER_PAGE)
    @attachments_count = @attachments.total_count
  end

  def download
    attachment = permitted_contact_attachments.find(params[:id])
    raise ActiveRecord::RecordNotFound unless attachment.file.attached?

    stream_authenticated_blob(download_blob_for(attachment))
  end

  private

  def permitted_contact_attachments
    conversations = Conversations::PermissionFilterService.new(
      Current.account.conversations.where(contact_id: @contact.id),
      Current.user,
      Current.account
    ).perform

    Attachment.where(account_id: Current.account.id)
              .where(message_id: Message.where(conversation_id: conversations).select(:id))
              .includes(file_attachment: :blob)
  end

  def download_blob_for(attachment)
    if params[:thumbnail].present? && attachment.image? && attachment.file.representable?
      attachment.file.variant(resize_to_fill: [250, 250]).processed.blob
    else
      attachment.file.blob
    end
  end
end
