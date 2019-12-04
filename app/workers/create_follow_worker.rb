class CreateFollowWorker
  include Sidekiq::Worker
  sidekiq_options queue: 'follow', retry: 0, backtrace: false

  def unique_key(request_id, options = {})
    request_id
  end

  # options:
  #   enqueue_location
  def perform(request_id, options = {})
    request = FollowRequest.find(request_id)
    CreateFollowTask.new(request).start!

  rescue FollowRequest::TooManyFollows => e
    logger.warn "#{e.class} Sleep for 1 hour"
    sleep 1.hour
    CreateFollowWorker.perform_async(request_id, options)

  rescue FollowRequest::RetryableError => e
    CreateFollowWorker.perform_async(request_id, options)

  rescue FollowRequest::AlreadyFollowing => e
    logger.warn e.inspect

  rescue => e
    logger.warn "Don't retry. #{e.class} #{e.message} #{request_id} #{options.inspect}"
    logger.warn "Caused by #{e.cause.inspect}" if e.cause
    logger.info e.backtrace.join("\n")
  end

  def self.fetch_one
    if Sidekiq::Queue.new('follow').size == 0
      request = FollowRequest.where(finished_at: nil).
          where(uid: User::EGOTTER_UID).
          where(error_class: '').
          order(created_at: :desc).first
      CreateFollowWorker.perform_async(request.id) if request
    end
  end
end
