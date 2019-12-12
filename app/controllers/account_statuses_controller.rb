# Always check the latest value without using the cache.
class AccountStatusesController < ApplicationController

  before_action :require_login!
  before_action :reject_crawler
  before_action { valid_uid?(params[:uid]) }

  before_action { create_search_log }

  def show
    uid = params[:uid].to_i
    status = AccountStatus.new

    begin
      request_context_client.twitter.user(uid)
    rescue => e
      status = AccountStatus.new(ex: e)
    end

    if status.unauthorized?
      return render json: {authorized: false}
    end

    CreateTwitterDBUserWorker.perform_async([uid], user_id: current_user.id, force_update: true)

    if status.not_found? || status.suspended?
      # TODO Create NotFoundUser or ForbiddenUser
      # user = TwitterUser.latest_by(uid: uid)
      # user = TwitterDB::User.find_by(uid: uid) unless user
      #
      # if user
      #   if status.not_found?
      #     CreateNotFoundUserWorker.perform_async(user.screen_name, uid: uid)
      #   elsif status.suspended?
      #     CreateForbiddenUserWorker.perform_async(user.screen_name, uid: uid)
      #   end
      # end
    end

    render json: {authorized: true, uid: uid, suspended: status.suspended?, not_found: status.not_found?}
  end
end
