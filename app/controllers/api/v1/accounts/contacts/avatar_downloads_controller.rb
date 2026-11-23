class Api::V1::Accounts::Contacts::AvatarDownloadsController < Api::V1::Accounts::BaseController
  include Contacts::AuthenticatedBlobDownloads

  before_action :set_contact
  before_action :authorize_contact_read!

  def show
    raise ActiveRecord::RecordNotFound unless @contact.avatar.attached?

    raise ActiveRecord::RecordNotFound unless @contact.avatar.representable?

    variant = @contact.avatar.variant(resize_to_fill: [250, nil]).processed
    stream_authenticated_blob(variant.blob)
  end

  private

  def set_contact
    @contact = Current.account.contacts.find(params[:id])
  end

  def authorize_contact_read!
    authorize @contact, :show?
  end
end
