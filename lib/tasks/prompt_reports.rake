namespace :prompt_reports do
  desc 'send'
  task send: :environment do
    sigint = Util::Sigint.new.trap

    logger = ActiveSupport::Logger.new(Rails.root.join('log/batch.log'))
    logger.level = Rails.logger.level
    logger.formatter = ::Logger::Formatter.new
    logger.extend ActiveSupport::Logger.broadcast(ActiveSupport::Logger.new(STDOUT))
    Rails.logger = logger

    task = PromptReportTask.start(user_ids_str: ENV['USER_IDS'], deadline_str: ENV['DEADLINE'])

    logger.info 'Started'
    logger.info task.to_s(:deadline) if task.deadline
    logger.info task.to_s(:ids_stats)

    task.users.find_each.with_index do |user, i|
      unless TwitterUser.exists?(uid: user.uid)
        # TwitterUser::Batch.fetch_and_create(user.uid) # TODO Create in background
        next
      end

      begin
        request = CreatePromptReportRequest.create(user_id: user.id)
        CreatePromptReportWorker.new.perform(request.id, user_id: user.id, exception: true)
      rescue => e
        task.add_error(user.id, e)
      end

      task.processed_count += 1
      logger.info task.to_s(:progress) if i % 1000 == 0

      break if task.overdue? || sigint.trapped? || task.fatal?
    end

    logger.info task.to_s(:finishing)
    logger.info 'Finished'

    if task.errors.any?
      logger.info "Errors:"
      logger.info task.to_s(:errors)
    end
  end
end
