class UnfollowsController < ApplicationController
  include Concerns::JobQueueingConcern

  before_action :reject_crawler
  before_action :require_login!
  before_action { valid_uid?(params[:uid]) }

  before_action {create_search_log(uid: params[:uid])}

  before_action do
    if !referer_is_tokimeki_unfollow? && !current_user.can_create_unfollow?
      render json: {
          create_unfollow_limit: current_user.create_unfollow_limit,
          create_unfollow_remaining: current_user.create_unfollow_remaining
      }, status: :too_many_requests
    end
  end

  def create
    user = current_user
    request = UnfollowRequest.new(user_id: user.id, uid: params[:uid])
    if request.save
      enqueue_create_follow_or_unfollow_job_if_needed(request, enqueue_location: 'UnfollowController')

      render json: {
          unfollow_request_id: request.id,
          create_unfollow_limit: user.create_unfollow_limit,
          create_unfollow_remaining: user.create_unfollow_remaining
      }
    else
      logger.warn "#{controller_name}##{action_name} #{request.errors.full_messages}"
      head :unprocessable_entity
    end
  end
end