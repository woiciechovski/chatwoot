class Api::V1::Accounts::Triage::ConversationsController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?
  before_action :set_execution, only: [:show, :transfer]

  def index
    executions = Current.account.conversation_flow_executions.in_triage
    executions = executions.includes(:conversation_flow, conversation: [:contact, :inbox, :team, :assignee])
    executions = filter_by_inbox(executions)
    executions = filter_by_search(executions)
    @executions = sort_executions(executions).page(params[:page]).per(25)
  end

  def show
    return head :not_found unless @execution.in_triage?

    render :show
  end

  def transfer
    team = Current.account.teams.find(params.require(:team_id))
    @execution = ConversationFlows::TransferService.new(execution: @execution, team: team, user: Current.user).perform
    render :show
  rescue ConversationFlows::TransferService::AlreadyTransferred
    render json: { error: I18n.t('conversation_flows.errors.already_transferred') }, status: :conflict
  rescue ConversationFlows::TransferService::InvalidTeam, ActiveRecord::RecordInvalid
    render json: { error: I18n.t('conversation_flows.errors.transfer_failed') }, status: :unprocessable_entity
  end

  private

  def sort_executions(executions)
    sort_by = params[:sort_by]
    return executions.order(:reserved_at, :id) unless Conversations::SortService::SORT_OPTIONS.key?(sort_by)

    sorted_conversations = Conversations::SortService.apply(Conversation.all, sort_by)
    executions.joins(:conversation).merge(sorted_conversations).order(:id)
  end

  def set_execution
    @execution = Current.account.conversation_flow_executions
                        .includes(:conversation_flow, conversation: [:contact, :inbox, :team, :assignee])
                        .joins(:conversation)
                        .find_by!(conversations: { display_id: params[:id] })
  end

  def filter_by_inbox(executions)
    return executions if params[:inbox_id].blank?

    inbox = Current.account.inboxes.find(params[:inbox_id])
    executions.joins(:conversation).where(conversations: { inbox_id: inbox.id })
  end

  def filter_by_search(executions)
    query = params[:q].to_s.strip
    return executions if query.blank?

    escaped_query = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
    contacts = Contact.arel_table
    conversations = Conversation.arel_table
    predicate = contacts[:name].matches(escaped_query)
                               .or(contacts[:email].matches(escaped_query))
                               .or(contacts[:phone_number].matches(escaped_query))
    predicate = predicate.or(conversations[:display_id].eq(query.to_i)) if query.match?(/\A\d+\z/)

    executions.joins(conversation: :contact).where(predicate)
  end
end
