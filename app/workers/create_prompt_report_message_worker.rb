class CreatePromptReportMessageWorker
  include Sidekiq::Worker
  include Concerns::AirbrakeErrorHandler
  sidekiq_options queue: 'messaging', retry: 0, backtrace: false

  def unique_key(user_id, options = {})
    user_id
  end

  def after_skip(user_id, options = {})
    log(Hashie::Mash.new(options)).update(status: false, error_class: DuplicateJobSkipped, error_message: "Direct message not sent #{user_id} #{options.inspect}")
  end

  class Unauthorized < StandardError
  end

  class DuplicateJobSkipped < StandardError
  end

  # options:
  #   kind
  #   changes_json
  #   previous_twitter_user_id
  #   current_twitter_user_id
  #   create_prompt_report_request_id
  def perform(user_id, options = {})
    user = User.find(user_id)
    unless user.authorized?
      log(options).update(status: false, error_class: Unauthorized, error_message: "Direct message not sent #{user_id} #{options.inspect}")
      return
    end

    kind = options['kind'].to_sym
    send_report(kind, user, options)
    send_warning_message(kind, user, options)

  rescue => e
    notify_airbrake(e, user_id: user_id, options: options)
    if DirectMessageStatus.you_have_blocked?(e) || (e.cause && DirectMessageStatus.you_have_blocked?(e.cause))
      CreateBlockedUserWorker.perform_async(user.uid, user.screen_name)
    elsif DirectMessageStatus.cannot_send_messages?(e)
    else
      logger.warn "#{e.inspect} #{user_id} #{options.inspect} #{"Caused by #{e.cause.inspect}" if e.cause}"
      logger.info e.backtrace.join("\n")
    end

    log(options).update(status: false, error_class: e.class, error_message: e.message)
  end

  def send_report(kind, user, options)
    if kind == :you_are_removed
      PromptReport.you_are_removed(*report_args(user, options)).deliver!
    elsif kind == :not_changed
      PromptReport.not_changed(*report_args(user, options)).deliver!
    elsif kind == :initialization
      PromptReport.initialization(
          user.id,
          request_id: options['create_prompt_report_request_id'],
          id: options['prompt_report_id'],
      ).deliver!
    else
      logger.warn "Invalid value #{kind}"
    end
  end

  def send_warning_message(kind, user, options)
    if kind == :you_are_removed || kind == :not_changed
      if !user.active_access?(CreatePromptReportRequest::ACTIVE_DAYS_WARNING)
        WarningMessage.inactive(user.id).deliver!
      elsif !user.following_egotter?
        WarningMessage.not_following(user.id).deliver!
      end
    elsif kind == :initialization
      log(options).update(status: false, error_class: CreatePromptReportRequest::InitializationStarted)
    else
      logger.warn "Invalid value #{kind}"
    end
  end

  def report_args(user, options)
    [
        user.id,
        {
            changes_json: options['changes_json'],
            previous_twitter_user: TwitterUser.find(options['previous_twitter_user_id']),
            current_twitter_user: TwitterUser.find(options['current_twitter_user_id']),
            request_id: options['create_prompt_report_request_id'],
            id: options['prompt_report_id'],
        }
    ]
  end

  def log(options)
    CreatePromptReportLog.find_or_initialize_by(request_id: options['create_prompt_report_request_id'])
  end
end
