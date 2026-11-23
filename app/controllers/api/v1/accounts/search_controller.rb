class Api::V1::Accounts::SearchController < Api::V1::Accounts::BaseController
  before_action :authorize_contact_search!, only: [:contacts]

  def index
    @result = search('all')
  end

  def conversations
    @result = search('Conversation')
  end

  def contacts
    @result = search('Contact')
  end

  def messages
    @result = search('Message')
  end

  def articles
    @result = search('Article')
  end

  private

  def authorize_contact_search!
    authorize Contact, :search?
  end

  def search(search_type)
    SearchService.new(
      current_user: Current.user,
      current_account: Current.account,
      search_type: search_type,
      params: params
    ).perform
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
