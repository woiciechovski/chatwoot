class Platform::Api::V1::UsersController < PlatformController
  # ref: https://stackoverflow.com/a/45190318/939299
  # set resource is called for other actions already in platform controller
  # we want to add login and token to that chain as well
  before_action(only: [:login, :token]) { set_resource }
  before_action(only: [:login, :token]) { validate_platform_app_permissible }

  def show; end

  def create
    @resource = (User.from_email(user_params[:email]) || User.new(user_params))
    validate_platform_app_permissible if @resource.persisted?
    return if performed?

    @resource.skip_confirmation!
    @resource.save!
    @platform_app.platform_app_permissibles.find_or_create_by!(permissible: @resource)
  end

  def login
    render json: { url: @resource.generate_sso_link }
  end

  def token; end

  def update
    @resource.assign_attributes(user_update_params)

    # We are using devise's reconfirmable flow for changing emails
    # But in case of platform APIs we don't want user to go through this extra step
    @resource.skip_reconfirmation! if user_update_params[:email].present?
    @resource.save!
  end

  def destroy
    user_to_delete, denial_memberships, accounts_by_id = user_deletion_state
    return deny_user_deletion(denial_memberships, accounts_by_id) if denial_memberships.any?

    DeleteObjectJob.perform_later(user_to_delete)
    head :ok
  end

  private

  def user_deletion_state
    user_to_delete = nil
    denial_memberships = []
    accounts_by_id = {}
    Rbac::MembershipLockService.with_user_memberships(user_id: @resource.id) do |accounts, user, memberships|
      denial_memberships = memberships.select(&:administrator?)
      accounts_by_id = accounts.index_by(&:id)
      user_to_delete = user if denial_memberships.empty?
    end
    [user_to_delete, denial_memberships, accounts_by_id]
  end

  def deny_user_deletion(memberships, accounts_by_id)
    memberships.each do |membership|
      Rbac::AuditEvents::Recorder.record_denied_safely!(
        account: accounts_by_id.fetch(membership.account_id),
        actor: @platform_app,
        action: 'user.delete.denied',
        target_type: 'AccountUser',
        target_id: membership.id,
        metadata: { request_id: request.request_id }
      )
    end
    render json: { error: I18n.t('errors.user.administrator_membership_must_be_removed') }, status: :unprocessable_entity
  end

  def user_custom_attributes
    return @resource.custom_attributes.merge(user_params[:custom_attributes]) if user_params[:custom_attributes]

    @resource.custom_attributes
  end

  def user_update_params
    # we want the merged custom attributes not the original one
    user_params.except(:custom_attributes).merge({ custom_attributes: user_custom_attributes })
  end

  def set_resource
    @resource = User.find(params[:id])
  end

  def user_params
    params.permit(:name, :display_name, :email, :password, custom_attributes: {})
  end
end
