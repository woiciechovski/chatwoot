class SuperAdmin::AccountUsersController < SuperAdmin::ApplicationController
  # Overwrite any of the RESTful controller actions to implement custom behavior
  # For example, you may want to send an email after a foo is updated.
  #

  # Since account/user page - account user role attribute links to the show page
  # Handle with a redirect to the user show page
  def show
    redirect_to super_admin_user_path(requested_resource.user)
  end

  def create
    resource = resource_class.new(resource_params)
    authorize_resource(resource)
    saved = save_account_user(resource)
    notice = saved ? translate_with_resource('create.success') : resource.errors.full_messages.first
    redirect_back(fallback_location: [namespace, resource.account], notice: notice)
  end

  def destroy
    result, denied_membership = destroy_account_user
    if result
      flash[:notice] = translate_with_resource('destroy.success')
    else
      copy_destroy_errors(denied_membership)
      record_denied_administrator_recovery(denied_membership) if denied_membership&.administrator?
      flash[:error] = requested_resource.errors.full_messages.join('<br/>')
    end
    redirect_back(fallback_location: [namespace, requested_resource.account])
  end

  # Override this method to specify custom lookup behavior.
  # This will be used to set the resource for the `show`, `edit`, and `update`
  # actions.
  #
  # def find_resource(param)
  #   Foo.find_by!(slug: param)
  # end

  # The result of this lookup will be available as `requested_resource`

  # Override this if you have certain roles that require a subset
  # this will be used to set the records shown on the `index` action.
  #
  # def scoped_resource
  #   if current_user.super_admin?
  #     resource_class
  #   else
  #     resource_class.with_less_stuff
  #   end
  # end

  # Override `resource_params` if you want to transform the submitted
  # data before it's persisted. For example, the following would turn all
  # empty values into nil values. It uses other APIs such as `resource_class`
  # and `dashboard`:
  #
  # def resource_params
  #   params.require(resource_class.model_name.param_key).
  #     permit(dashboard.permitted_attributes).
  #     transform_values { |value| value == "" ? nil : value }
  # end

  private

  def save_account_user(resource)
    return resource.save unless resource.account_id.present? && resource.user_id.present?

    Rbac::MembershipLockService.with_membership(account_id: resource.account_id, user_id: resource.user_id) do |account, user, _membership|
      resource.account = account
      resource.user = user
      saved = resource.save
      record_administrator_recovery(resource) if saved && resource.administrator?
      saved
    end
  end

  def destroy_account_user
    result = nil
    denied_membership = nil
    Rbac::MembershipLockService.with_account(account_id: requested_resource.account_id) do |account|
      membership = account.account_users.find_by(id: requested_resource.id)
      next unless membership

      Rbac::MembershipLockService.with_membership(
        account_id: account.id,
        user_id: membership.user_id,
        membership_id: membership.id
      ) do |_locked_account, _user, locked_membership|
        result = locked_membership.destroy
        denied_membership = locked_membership unless result
      end
    end
    [result, denied_membership]
  end

  def copy_destroy_errors(denied_membership)
    requested_resource.errors.copy!(denied_membership.errors) if denied_membership && requested_resource.errors.empty?
    return unless requested_resource.errors.empty?

    requested_resource.errors.add(:base, I18n.t('errors.account_user.last_administrator'))
  end

  def record_administrator_recovery(account_user)
    Rbac::AuditEvents::Recorder.record!(
      account: account_user.account,
      actor: current_super_admin,
      action: 'administrator.recovery.granted',
      target: account_user,
      metadata: { request_id: request.request_id }
    )
  end

  def record_denied_administrator_recovery(account_user)
    return unless account_user.errors.details.values.flatten.any? { |detail| detail[:error] == :last_administrator }

    Rbac::AuditEvents::Recorder.record_denied_safely!(
      account: account_user.account,
      actor: current_super_admin,
      action: 'administrator.recovery.removal.denied',
      target_type: 'AccountUser',
      target_id: account_user.id,
      metadata: { request_id: request.request_id }
    )
  end

  # See https://administrate-prototype.herokuapp.com/customizing_controller_actions
  # for more information
end
