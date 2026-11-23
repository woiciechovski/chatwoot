class Api::V1::Accounts::AgentsController < Api::V1::Accounts::BaseController
  before_action :fetch_agent, except: [:create, :index, :bulk_create]
  before_action :check_authorization

  def index
    @agents = agents
  end

  def create
    builder = AgentBuilder.new(
      email: new_agent_params['email'],
      name: new_agent_params['name'],
      role: new_agent_params['role'],
      availability: new_agent_params['availability'],
      auto_offline: new_agent_params['auto_offline'],
      inviter: current_user,
      account: Current.account
    )

    @agent = builder.perform
  rescue AgentBuilder::LimitExceededError => e
    render_payment_required(e.message)
  end

  def update
    account = Current.account
    actor = Current.account_user
    attributes = agent_params
    user_attributes = attributes.slice(:name).compact
    membership_attributes = attributes.slice(*account_user_attributes).compact

    if membership_attributes.key?(:role)
      update_agent_with_locked_membership(user_attributes, membership_attributes)
    else
      @agent.update!(user_attributes)
      @agent.current_account_user.update!(membership_attributes)
    end
  rescue ActiveRecord::RecordInvalid => e
    record_denied_administrator_change(account, actor, e.record, 'administrator.demotion.denied')
    raise
  end

  def destroy
    account = Current.account
    actor = Current.account_user
    @agent.current_account_user.destroy!
    delete_user_record(@agent)
    head :ok
  rescue ActiveRecord::RecordNotDestroyed => e
    record_denied_administrator_change(account, actor, e.record, 'administrator.removal.denied')
    render json: { message: e.record.errors.full_messages.join(', '), attributes: e.record.errors.attribute_names },
           status: :unprocessable_entity
  end

  def bulk_create
    emails = params[:emails]

    bulk_create_agents(emails)
    # This endpoint is used to bulk create agents during onboarding
    # onboarding_step key in present in Current account custom attributes, since this is a one time operation
    clear_onboarding_step
    head :ok
  rescue AgentBuilder::LimitExceededError => e
    render_payment_required(e.message)
  end

  private

  def check_authorization
    super(User)
  end

  def fetch_agent
    @agent = agents.find(params[:id])
  end

  def account_user_attributes
    [:role, :availability, :auto_offline]
  end

  def update_agent_with_locked_membership(user_attributes, membership_attributes)
    Rbac::MembershipLockService.with_membership(
      account_id: Current.account.id,
      user_id: @agent.id,
      membership_id: @agent.current_account_user.id
    ) do |_account, _user, membership|
      @agent.update!(user_attributes)
      membership.update!(membership_attributes)
      @agent.reload
    end
  end

  def allowed_agent_params
    [:name, :email, :role, :availability, :auto_offline]
  end

  def agent_params
    params.require(:agent).permit(allowed_agent_params)
  end

  def new_agent_params
    params.require(:agent).permit(:email, :name, :role, :availability, :auto_offline)
  end

  def agents
    @agents ||= Current.account.users.order_by_full_name.includes(:account_users, { avatar_attachment: [:blob] })
  end

  def bulk_create_agents(emails)
    email_limit_error = nil

    exceeds_capacity = Rbac::MembershipLockService.with_account(account_id: Current.account.id) do |account|
      emails.count > available_agent_count(account)
    end
    raise AgentBuilder::LimitExceededError if exceeds_capacity

    emails.each do |email|
      create_agent_from_email(email)
    rescue CustomExceptions::Account::EmailLimitExceeded => e
      email_limit_error = e
    end

    raise email_limit_error if email_limit_error
  end

  def create_agent_from_email(email)
    builder = AgentBuilder.new(
      email: email,
      name: email.split('@').first,
      inviter: current_user,
      account: Current.account
    )
    builder.perform
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.info "[Agent#bulk_create] ignoring email #{email}, errors: #{e.record.errors}"
  end

  def clear_onboarding_step
    Current.account.custom_attributes.delete('onboarding_step')
    Current.account.save!
  end

  def available_agent_count(account = Current.account)
    account.usage_limits[:agents] - account.account_users.count
  end

  def delete_user_record(agent)
    DeleteObjectJob.perform_later(agent) if agent.reload.account_users.blank?
  end

  def record_denied_administrator_change(account, actor, account_user, action)
    return unless account_user.is_a?(AccountUser)
    return unless account_user.errors.details.values.flatten.any? { |detail| detail[:error] == :last_administrator }

    Rbac::AuditEvents::Recorder.record_denied_safely!(
      account: account,
      actor: actor,
      action: action,
      target_type: 'AccountUser',
      target_id: account_user.id,
      metadata: { request_id: request.request_id }
    )
  end
end

Api::V1::Accounts::AgentsController.prepend_mod_with('Api::V1::Accounts::AgentsController')
