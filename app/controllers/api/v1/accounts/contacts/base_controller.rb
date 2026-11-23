class Api::V1::Accounts::Contacts::BaseController < Api::V1::Accounts::BaseController
  before_action :ensure_contact

  private

  def ensure_contact
    @contact = Current.account.contacts.find(params[:contact_id])
  end

  def authorize_contact_read!
    authorize @contact, :show?
  end

  def authorize_contact_update!
    authorize @contact, :update?
  end
end
