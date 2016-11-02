class UpdateTwitterUserWorker
  include Sidekiq::Worker
  sidekiq_options queue: :egotter, retry: false, backtrace: false

  def perform(user_id)
    user = User.find(user_id)
    uid = user.uid.to_i
    log = BackgroundUpdateLog.new(
      user_id:     user.id,
      uid:         uid,
      screen_name: user.screen_name,
      bot_uid:     user.uid
    )
    client = user.api_client
    Rollbar.scope!(person: {id: user.id, username: user.screen_name, email: ''})

    unless user.authorized?
      return
    end

    existing_tu = TwitterUser.latest(uid)
    if existing_tu.present? && existing_tu.fresh?
      existing_tu.increment(:update_count).save
      log.update(status: true, call_count: client.call_count, message: "[#{existing_tu.id}] is recently updated.")
      notify(user, existing_tu)
      return
    end

    # If friends is increased by NUM and friends is decremented by same NUM, the blow code makes a wrong decision.
    # t_user = client.user(uid)
    # if existing_tu.present? && existing_tu.friends_count == t_user.friends_count && existing_tu.followers_count == t_user.followers_count
    #   existing_tu.increment(:update_count).save
    #   log.update(status: true, call_count: client.call_count, message: "[#{existing_tu.id}] is probably not changed.")
    #   notify(user, existing_tu)
    #   return
    # end

    new_tu = TwitterUser.build_with_relations(client.user(uid), client: client, login_user: user, context: :update)
    new_tu.user_id = user.id
    if new_tu.friendless?
      log.update(status: true, call_count: client.call_count, message: "[#{new_tu.screen_name}] has too many friends.")
      return
    end

    if new_tu.save
      new_tu.increment(:update_count).save
      log.update(status: true, call_count: client.call_count, message: "[#{new_tu.id}] is created.")
      notify(user, new_tu, created: true)
      return
    end

    if existing_tu.present?
      existing_tu.increment(:update_count).save
      log.update(status: true, call_count: client.call_count, message: "[#{existing_tu.id}] is not changed.")
      notify(user, existing_tu)
      return
    end

    log.update(
      status: false,
      call_count: client.call_count,
      reason: BackgroundSearchLog::SomethingError::MESSAGE,
      message: "#{new_tu.errors.full_messages.join(', ')}."
    )
    Rollbar.warn(e)
  rescue Twitter::Error::TooManyRequests => e
    log.update(
      status: false,
      call_count: client.call_count,
      reason: BackgroundSearchLog::TooManyRequests::MESSAGE,
      message: ''
    )
    Rollbar.warn(e)
  rescue Twitter::Error::Unauthorized => e
    user.update(authorized: false)
    log.update(
      status: false,
      call_count: client.call_count,
      reason: BackgroundSearchLog::Unauthorized::MESSAGE,
      message: ''
    )
    Rollbar.warn(e)
  rescue => e
    logger.warn "#{self.class}##{__method__}: #{e.class} #{e.message}"
    logger.info e.backtrace.slice(0, 10).join("\n")
    log.update(
      status: false,
      call_count: client.call_count,
      reason: BackgroundSearchLog::SomethingError::MESSAGE,
      message: "#{e.class} #{e.message}"
    )
    Rollbar.warn(e)
  end

  def notify(login_user, tu, created: false)
    ::Cache::PageCache.new.delete(tu.uid) if created

    %w(dm onesignal).each do |medium|
      CreateNotificationMessageWorker.perform_async(login_user.id, tu.uid.to_i, tu.screen_name, type: 'update', medium: medium)
    end
  rescue => e
    logger.warn "#{self.class}##{__method__}: #{e.class} #{e.message} #{login_user.inspect} #{tu.inspect}"
    Rollbar.warn(e)
  end
end
