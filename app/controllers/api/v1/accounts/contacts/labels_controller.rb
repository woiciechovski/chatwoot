class Api::V1::Accounts::Contacts::LabelsController < Api::V1::Accounts::Contacts::BaseController
  include LabelConcern

  def index
    authorize_contact_read!
    super
  end

  def create
    authorize_contact_update!
    super
    head :no_content unless policy(@contact).show?
  end

  private

  def model
    @model ||= @contact
  end

  def permitted_params
    params.permit(labels: [])
  end
end
