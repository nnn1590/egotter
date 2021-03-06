namespace :users do
  desc 'update authorized'
  task update_authorized: :environment do
    sigint = Util::Sigint.new.trap

    # Avoid circular dependency
    ApiClient
    CacheDirectory

    green = -> (str) {print "\e[32m#{str}\e[0m"}
    red = -> (str) {print "\e[31m#{str}\e[0m"}
    start = ENV['START'] ? ENV['START'].to_i : 1

    User.authorized.find_in_batches(start: start, batch_size: 200) do |users|
      Parallel.each(users, in_threads: 10) do |user|
        begin
          t_user = user.api_client.verify_credentials
          user.screen_name = t_user[:screen_name]
          green.call('.')
        rescue Twitter::Error::ServiceUnavailable => e
          puts "#{e.class} #{e.message}"
          retry
        rescue => e
          if e.message == 'Invalid or expired token.'
            user.authorized = false
            red.call('.')
          else
            puts "Failed #{user.id}"
            raise
          end
        end
      end

      puts "\n"

      authorized_changed = users.select(&:authorized_changed?)
      if authorized_changed.any?
        puts "Import authorized_changed #{authorized_changed.size}"
        Rails.logger.silence { User.import(authorized_changed, on_duplicate_key_update: %i(uid authorized), validate: false) }
      end

      screen_name_changed = users.select(&:screen_name_changed?)
      if screen_name_changed.any?
        puts "Import screen_name_changed #{screen_name_changed.size}"
        Rails.logger.silence { User.import(screen_name_changed, on_duplicate_key_update: %i(uid screen_name), validate: false) }
      end

      puts "Last id #{users[-1].id}"

      break if sigint.trapped?
    end
  end

  desc 'update timestamps'
  task update_timestamps: :environment do
    start_day = ENV['START'] ? Time.zone.parse(ENV['START']) : (Time.zone.now - 30.days)
    end_day = ENV['END'] ? Time.zone.parse(ENV['END']) : Time.zone.now

    puts "users:update start #{Time.zone.now}"

    (start_day.to_date..end_day.to_date).each do |day|
      search_logs = SearchLog.with_login.where(created_at: day.to_time.all_day).order(created_at: :asc)
      users = User.where(id: search_logs.uniq.pluck(:user_id)).index_by(&:id)

      search_logs.select(:user_id, :created_at).each do |log|
        user = users[log.user_id]
        users_assign_timestamp(user, :first_access_at, log.created_at) { |_user, attr, value| _user[attr] > value }
        users_assign_timestamp(user, :last_access_at, log.created_at) { |_user, attr, value| _user[attr] < value }
      end

      search_logs.where(action: 'show').select(:user_id, :created_at).each do |log|
        user = users[log.user_id]
        users_assign_timestamp(user, :first_search_at, log.created_at) { |_user, attr, value| _user[attr] > value }
        users_assign_timestamp(user, :last_search_at, log.created_at) { |_user, attr, value| _user[attr] < value }
      end

      SignInLog.where(created_at: day.to_time.all_day, user_id: users.keys).select(:user_id, :created_at).each do |log|
        user = users[log.user_id]
        users_assign_timestamp(user, :first_sign_in_at, log.created_at) { |_user, attr, value| _user[attr] > value }
        users_assign_timestamp(user, :last_sign_in_at, log.created_at) { |_user, attr, value| _user[attr] < value }
      end

      changed, not_changed = users.values.partition { |u| u.changed? }
      puts "#{day} users: #{users.size}, changed: #{changed.size}, not changed: #{not_changed.size}"

      if changed.any?
        User.import changed, on_duplicate_key_update: %i(first_access_at last_access_at first_search_at last_search_at first_sign_in_at last_sign_in_at), validate: false, timestamps: false
      end
    end

    puts "users:update finish #{Time.zone.now}"
  end

  def users_assign_timestamp(user, attr, value)
    if user[attr].nil? || yield(user, attr, value)
      user[attr] = value
    end
  end
end
