class CreateWelcomeMessageWorker
  include Sidekiq::Worker
  include Concerns::WorkerUtils
  sidekiq_options queue: self, retry: 0, backtrace: false

  def perform(user_id)
    user = User.find(user_id)
    return unless user.authorized?

    queue = RunningQueue.new(self.class)
    return if queue.exists?(user.uid)
    queue.add(user.uid)

    WelcomeMessage.welcome(user.id).deliver

  rescue Twitter::Error::Unauthorized => e
    handle_unauthorized_exception(e, user_id: user_id)
  rescue Twitter::Error::Forbidden => e
    if e.message == 'You are sending a Direct Message to users that do not follow you.'
      logger.info "#{e.class}: #{e.message} #{user_id}"
    else
      logger.warn "#{e.class}: #{e.message} #{user_id}"
    end
    logger.info e.backtrace.join("\n")
  rescue => e
    logger.warn "#{e.class}: #{e.message.truncate(150)} #{user_id}"
    logger.info e.backtrace.join("\n")
  end
end
