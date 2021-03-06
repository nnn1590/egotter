class FetchUserForCachingWorker
  include Sidekiq::Worker
  sidekiq_options queue: 'misc', retry: 0, backtrace: false

  def unique_key(uid_or_screen_name, options = {})
    # This value is always used as string.
    uid_or_screen_name
  end

  def unique_in
    1.minute
  end

  def expire_in
    1.minute
  end

  def timeout_in
    5.seconds
  end

  def after_timeout(uid_or_screen_name, options = {})
    # Do nothing.
  end

  # options:
  #   user_id
  def perform(uid_or_screen_name, options = {})
    client = options['user_id'] ? User.find(options['user_id']).api_client : Bot.api_client
    client.user(uid_or_screen_name)
  rescue => e
    status = AccountStatus.new(ex: e)

    if status.not_found? || status.suspended? || status.unauthorized? || status.too_many_requests?
    else
      logger.warn "#{e.inspect} #{uid_or_screen_name} #{options.inspect}"
      logger.info e.backtrace.join("\n")
    end
  end
end
