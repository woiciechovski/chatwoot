class Api::V1::Accounts::ConversationFlowsController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?
  before_action :set_conversation_flow, only: [:show, :update]

  def index
    @conversation_flows = Current.account.conversation_flows.includes(:inboxes).order(:id)
  end

  def show; end

  def create
    attributes = conversation_flow_params
    inbox_ids = attributes.delete(:inbox_ids) || []
    @conversation_flow = Current.account.conversation_flows.new(attributes)
    @conversation_flow.created_by = Current.user
    @conversation_flow.updated_by = Current.user

    ActiveRecord::Base.transaction do
      @conversation_flow.save!
      assign_inboxes(inbox_ids)
    end

    render :show, status: :created
  end

  def update
    attributes = conversation_flow_params
    inbox_ids = attributes.delete(:inbox_ids)

    ActiveRecord::Base.transaction do
      @conversation_flow.assign_attributes(attributes)
      @conversation_flow.updated_by = Current.user
      @conversation_flow.save!
      assign_inboxes(inbox_ids) if inbox_ids
    end

    render :show
  end

  private

  def set_conversation_flow
    @conversation_flow = Current.account.conversation_flows.includes(:inboxes).find(params[:id])
  end

  def conversation_flow_params
    attributes = params.require(:conversation_flow)
    raise ActionController::BadRequest, 'inbox_ids must be an array' if attributes.key?(:inbox_ids) && !attributes[:inbox_ids].is_a?(Array)

    attributes.permit(:name, :description, :enabled, inbox_ids: [])
  end

  def assign_inboxes(inbox_ids)
    return if inbox_ids.empty? && @conversation_flow.inboxes.empty?

    inboxes = Current.account.inboxes.where(id: inbox_ids).to_a
    raise ActiveRecord::RecordNotFound unless inboxes.size == inbox_ids.uniq.size

    @conversation_flow.inboxes = inboxes
  end
end
