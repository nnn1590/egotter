class SendMetricsToSlackWorker
  include Sidekiq::Worker
  sidekiq_options queue: 'misc', retry: 0, backtrace: false

  def unique_key(steps = nil)
    steps.inspect
  end

  def unique_in
    5.minutes
  end

  def perform(steps = nil)
    unless steps
      steps = [
          :send_table_metrics,
          :send_user_metrics,
          :send_twitter_user_metrics,
          :send_google_analytics_metrics,
          :send_sidekiq_queue_metrics,
          :send_sidekiq_worker_metrics,
          :send_nginx_metrics,
          :send_search_histories_metrics,
          :send_visitors_metrics,
          :send_sign_in_metrics,
          :send_prompt_report_metrics,
          :send_prompt_report_error_metrics,
          :send_rate_limit_metrics,
          :send_search_error_metrics,
      ]
    end

    do_perform(steps.shift)
    self.class.perform_async(steps) if steps.any?
  end

  def do_perform(step)
    send(step)
  rescue => e
    logger.warn "#{e.class} #{e.message} #{step}"
    logger.info e.backtrace.join("\n")
  end

  def send_table_metrics
    values = Gauge.where(time: 10.minutes.ago..Time.zone.now).where(name: 'tables').map {|g| [g.label, g.value]}.to_h
    SlackClient.send_message(SlackClient.format(values), title: 'tables', channel: SlackClient::TABLE_MONITORING)
  end

  def send_twitter_user_metrics
    values = Gauge.where(time: 10.minutes.ago..Time.zone.now).where(name: 'twitter_user').map {|g| [g.label, g.value]}.to_h
    SlackClient.send_message(SlackClient.format(values), title: 'twitter_user', channel: SlackClient::TWITTER_USERS_MONITORING)

    friends_count = []
    followers_count = []
    friends_size = []
    followers_size = []

    users.each do |user|
      friends_count << user.friends_count
      followers_count << user.followers_count
      friends_size << user.friends_size
      followers_size << user.followers_size
    end
    size = users.size

    stats = {
        friends_count: {
            avg: sprintf("%.1f", divide(friends_count.sum, size)),
            min: friends_count.min,
            max: friends_count.max
        },
        followers_count: {
            avg: sprintf("%.1f", divide(followers_count.sum, size)),
            min: followers_count.min,
            max: followers_count.max
        },
        friends_size: {
            avg: sprintf("%.1f", divide(friends_size.sum, size)),
            min: friends_size.min,
            max: friends_size.max
        },
        followers_size: {
            avg: sprintf("%.1f", divide(followers_size.sum, size)),
            min: followers_size.min,
            max: followers_size.max
        }
    }

    SlackClient.send_message(SlackClient.format(stats), channel: SlackClient::TWITTER_USERS_MONITORING)
  end

  def send_google_analytics_metrics
    values = Gauge.where(time: 10.minutes.ago..Time.zone.now).where(name: 'ga rt:activeUsers').map {|g| [g.label, g.value]}.to_h
    SlackClient.send_message(SlackClient.format(values), title: 'ga rt:activeUsers', channel: SlackClient::GA_MONITORING)
  end

  def send_prompt_report_metrics
    condition = {created_at: 1.hour.ago..Time.zone.now}
    stats = {
        prompt_reports: PromptReport.where(condition).size,
        'prompt_reports(read)' => PromptReport.where(condition.merge(read_at: 1.hour.ago..Time.zone.now)).size,
        'prompt_reports(timelines)' => SearchLog.where(condition).where(via: 'prompt_report_shortcut').size,
        create_prompt_report_logs: CreatePromptReportLog.where(condition).size,
    }

    SlackClient.send_message(SlackClient.format(stats), channel: SlackClient::MESSAGING_MONITORING)
    Gauge.create_by_hash('prompt_report', stats)
  end

  def send_prompt_report_error_metrics
    condition = {created_at: 1.hour.ago..Time.zone.now}
    stats =
        CreatePromptReportLog.select('error_class, count(*) cnt').
            where(condition).
            group('error_class').
            order('cnt desc').map do |record|
          [record.error_class, record.cnt]
        end.to_h

    stats.transform_keys! do |key|
      if key.include?(':')
        key.split(':')[-1]
      elsif key.empty?
        'EMPTY'
      else
        key
      end
    end

    SlackClient.send_message(SlackClient.format(stats), channel: SlackClient::MESSAGING_MONITORING)
    Gauge.create_by_hash('prompt_report_error', stats)
  end

  def send_sidekiq_queue_metrics
    queues = Sidekiq::Queue.all.select {|queue| queue.latency > 0}.sort_by(&:name)
    queues = queues.map do |queue|
      [queue.name, {size: queue.size, latency: sprintf("%.3f", queue.latency)}]
    end.to_h
    SlackClient.send_message(SlackClient.format(queues), title: 'queues', channel: SlackClient::SIDEKIQ_MONITORING)
  end

  def send_sidekiq_worker_metrics(types = nil)
    unless types
      types = Rails.env.development? ? %w(sidekiq_all) : %w(sidekiq sidekiq_misc sidekiq_import sidekiq_prompt_reports)
    end

    types.each do |type|
      stats = SidekiqStats.new(type).to_a.sort_by {|k, _| k}.to_h
      SlackClient.send_message(SlackClient.format(stats), title: type, channel: SlackClient::SIDEKIQ_MONITORING)
    end
  end

  def send_nginx_metrics
    SlackClient.send_message(__method__)

    stats = NginxStats.new
    SlackClient.send_message(SlackClient.format(stats))
  end

  def send_search_histories_metrics
    channel = SlackClient::SEARCH_HISTORIES_MONITORING
    histories = SearchHistory.where(created_at: 1.hour.ago..Time.zone.now)

    stats = {
        size: histories.size,
        unique_uid: histories.select('distinct uid').count,
        unique_user_id: histories.select('distinct user_id').count,
    }
    SlackClient.send_message(SlackClient.format(stats), channel: channel)
    Gauge.create_by_hash('search_histories', stats)

    stats = histories.each_with_object(Hash.new(0)).each {|his, memo| memo[his.via] += 1}.sort_by {|_, v| -v}.to_h
    SlackClient.send_message(SlackClient.format(stats), title: 'total (via)', channel: channel)
    Gauge.create_by_hash('search_histories via', stats)

    stats = histories.each_with_object(Hash.new(0)).each {|his, memo| memo[his.last_session_source] += 1}.sort_by {|_, v| -v}.to_h
    SlackClient.send_message(SlackClient.format(stats), title: 'total (source)', channel: channel)
    Gauge.create_by_hash('search_histories source', stats)

    stats = histories.each_with_object(Hash.new(0)).each {|his, memo| memo[his.last_session_device_type] += 1}.sort_by {|_, v| -v}.to_h
    SlackClient.send_message(SlackClient.format(stats), title: 'total (device_type)', channel: channel)
    Gauge.create_by_hash('search_histories device_type', stats)
  end

  def send_visitors_metrics
    condition = {created_at: 1.hour.ago..Time.zone.now}
    visitors = Visitor.where(condition)

    stats = {
        size: visitors.size,
        unique_user_id: visitors.select('distinct user_id').count,
    }
    SlackClient.send_message(SlackClient.format(stats), channel: SlackClient::VISITORS_MONITORING)
    Gauge.create_by_hash('visitors', stats)

    stats = visitors.each_with_object(Hash.new(0)).each {|vis, memo| memo[vis.last_session_via] += 1}.sort_by {|_, v| -v}.to_h
    SlackClient.send_message(SlackClient.format(stats), title: 'total (via)', channel: SlackClient::VISITORS_MONITORING)
    Gauge.create_by_hash('visitors via', stats)

    stats = visitors.each_with_object(Hash.new(0)).each {|vis, memo| memo[vis.last_session_source] += 1}.sort_by {|_, v| -v}.to_h
    SlackClient.send_message(SlackClient.format(stats), title: 'total (source)', channel: SlackClient::VISITORS_MONITORING)
    Gauge.create_by_hash('visitors source', stats)

    stats = visitors.each_with_object(Hash.new(0)).each {|vis, memo| memo[vis.last_session_device_type] += 1}.sort_by {|_, v| -v}.to_h
    SlackClient.send_message(SlackClient.format(stats), title: 'total (device_type)', channel: SlackClient::VISITORS_MONITORING)
    Gauge.create_by_hash('visitors device_type', stats)
  end

  def send_user_metrics
    condition_value = 1.hour.ago..Time.zone.now
    stats = {
        creation: User.where(created_at: condition_value).size,
        first_access: User.where(first_access_at: condition_value).size,
        last_access: User.where(last_access_at: condition_value).size
    }
    SlackClient.send_message(SlackClient.format(stats), channel: SlackClient::USERS_MONITORING)
    Gauge.create_by_hash('users', stats)

    users = User.where(created_at: condition_value)

    stats = users.each_with_object(Hash.new(0)).each {|vis, memo| memo[vis.last_session_via] += 1}.sort_by {|_, v| -v}.to_h
    SlackClient.send_message(SlackClient.format(stats), title: 'total (via)', channel: SlackClient::USERS_MONITORING)
    Gauge.create_by_hash('users via', stats)

    stats = users.each_with_object(Hash.new(0)).each {|vis, memo| memo[vis.last_session_source] += 1}.sort_by {|_, v| -v}.to_h
    SlackClient.send_message(SlackClient.format(stats), title: 'total (source)', channel: SlackClient::USERS_MONITORING)
    Gauge.create_by_hash('users source', stats)

    stats = users.each_with_object(Hash.new(0)).each {|vis, memo| memo[vis.last_session_device_type] += 1}.sort_by {|_, v| -v}.to_h
    SlackClient.send_message(SlackClient.format(stats), title: 'total (device_type)', channel: SlackClient::USERS_MONITORING)
    Gauge.create_by_hash('users device_type', stats)
  end

  def send_sign_in_metrics
    logs = SignInLog.where(created_at: 1.hour.ago..Time.zone.now)

    stats = {
        size: logs.size,
        create: logs.where(context: 'create').size,
        update: logs.where(context: 'update').size,
    }
    SlackClient.send_message(SlackClient.format(stats), channel: SlackClient::SIGN_IN_MONITORING)
    Gauge.create_by_hash('sign_in', stats)

    stats = logs.each_with_object(Hash.new(0)).each {|log, memo| memo[log.via] += 1}.sort_by {|_, v| -v}.to_h
    SlackClient.send_message(SlackClient.format(stats), title: 'total (via)', channel: SlackClient::SIGN_IN_MONITORING)
    Gauge.create_by_hash('sign_in via', stats)

    stats = logs.each_with_object(Hash.new(0)).each {|log, memo| memo[log.via] += 1 if log.context == 'create'}.sort_by {|_, v| -v}.to_h
    SlackClient.send_message(SlackClient.format(stats), title: 'create (via)', channel: SlackClient::SIGN_IN_MONITORING)
    Gauge.create_by_hash('sign_in via (create)', stats)

    stats = logs.each_with_object(Hash.new(0)).each {|log, memo| memo[log.via] += 1 if log.context == 'update'}.sort_by {|_, v| -v}.to_h
    SlackClient.send_message(SlackClient.format(stats), title: 'update (via)', channel: SlackClient::SIGN_IN_MONITORING)
    Gauge.create_by_hash('sign_in via (update)', stats)

    stats = logs.each_with_object(Hash.new(0)).each {|log, memo| memo[log.last_session_source] += 1}.sort_by {|_, v| -v}.to_h
    SlackClient.send_message(SlackClient.format(stats), title: 'total (source)', channel: SlackClient::SIGN_IN_MONITORING)
    Gauge.create_by_hash('sign_in source', stats)

    stats = logs.each_with_object(Hash.new(0)).each {|log, memo| memo[log.device_type] += 1}.sort_by {|_, v| -v}.to_h
    SlackClient.send_message(SlackClient.format(stats), title: 'total (device_type)', channel: SlackClient::SIGN_IN_MONITORING)
    Gauge.create_by_hash('sign_in device_type', stats)
  end

  def send_rate_limit_metrics
    stats =
        Bot.rate_limit.map do |limit|
          id = limit.delete(:id).to_s
          values = limit.map {|key, value| [key, value[:remaining]]}.to_h
          [id, values]
        end.to_h

    SlackClient.send_message(SlackClient.format(stats), channel: SlackClient::RATE_LIMIT_MONITORING)
  end

  def send_search_error_metrics
    logs = SearchErrorLog.where(created_at: 1.hour.ago..Time.zone.now).
        where.not(device_type: 'crawler').
        where.not(session_id: '-1')

    stats = logs.each_with_object(Hash.new(0)).each {|log, memo| memo[log.location] += 1}.sort_by {|_, v| -v}.to_h
    SlackClient.send_message(SlackClient.format(stats), title: 'total (location)', channel: SlackClient::SEARCH_ERROR_MONITORING)

    stats = logs.each_with_object(Hash.new(0)).each {|log, memo| memo[log.location] += 1 if log.user_found?}.sort_by {|_, v| -v}.to_h
    SlackClient.send_message(SlackClient.format(stats), title: 'user (location)', channel: SlackClient::SEARCH_ERROR_MONITORING)

    stats = logs.each_with_object(Hash.new(0)).each {|log, memo| memo[log.location] += 1 unless log.user_found?}.sort_by {|_, v| -v}.to_h
    SlackClient.send_message(SlackClient.format(stats), title: 'visitor (location)', channel: SlackClient::SEARCH_ERROR_MONITORING)

    stats = logs.each_with_object(Hash.new(0)).each {|log, memo| memo[log.via] += 1}.sort_by {|_, v| -v}.to_h
    SlackClient.send_message(SlackClient.format(stats), title: 'total (via)', channel: SlackClient::SEARCH_ERROR_MONITORING)

    stats = logs.each_with_object(Hash.new(0)).each {|log, memo| memo[log.last_session_source] += 1}.sort_by {|_, v| -v}.to_h
    SlackClient.send_message(SlackClient.format(stats), title: 'total (source)', channel: SlackClient::SEARCH_ERROR_MONITORING)

    stats = logs.each_with_object(Hash.new(0)).each {|log, memo| memo[log.device_type] += 1}.sort_by {|_, v| -v}.to_h
    SlackClient.send_message(SlackClient.format(stats), title: 'total (device_type)', channel: SlackClient::SEARCH_ERROR_MONITORING)
  end

  def divide(num1, num2)
    num1 / num2
  rescue ZeroDivisionError => e
    0
  end
end
