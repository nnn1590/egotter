require 'active_support/concern'

module Concerns::TwitterDB::User::Batch
  extend ActiveSupport::Concern

  # `follower_ids` includes suspended uids.
  # `followers` does not include suspended uids.
  # `followers_count` is ambiguous.
  class Batch
    def self.fetch_and_import!(uids, client:, force_update: false)
      uids = uids.uniq.map(&:to_i)
      users = fetch(uids, client: client)
      imported = import(users, force_update: force_update)
      import_suspended(uids - users.map { |u| u[:id] }) if uids.size != imported.size
    end

    def self.fetch(uids, client:)
      client.users(uids)
    rescue Twitter::Error::NotFound => e
      if e.message == 'No user matches for specified terms.'
        []
      else
        raise
      end
    end

    def self.import(t_users, force_update: false)
      unless force_update
        # Note: This process uses index_twitter_db_users_on_uid instead of index_twitter_db_users_on_updated_at.
        persisted_uids = TwitterDB::User.where(uid: t_users.map {|user| user[:id]}, updated_at: 1.days.ago..Time.zone.now).pluck(:uid)
        t_users = t_users.reject {|user| persisted_uids.include? user[:id]}
      end

      retry_importing { TwitterDB::User.import_by!(users: t_users) }

      t_users
    end

    def self.import_suspended(uids)
      not_persisted = uids.uniq.map(&:to_i) - TwitterDB::User.where(uid: uids).pluck(:uid)
      return [] if not_persisted.empty?

      t_users =  not_persisted.map { |uid| Hashie::Mash.new(id: uid, screen_name: 'suspended', description: '') }
      import(t_users)

      if not_persisted.size >= 10
        logger.warn {"#{self.class}##{__method__} #{not_persisted.size} records"}
      else
        logger.info {"#{self.class}##{__method__} #{not_persisted.size} records"}
      end

      not_persisted
    end

    private

    def self.logger
      @@logger ||= (File.basename($0) == 'rake' ? Logger.new(STDOUT) : Rails.logger)
    end

    def self.retry_importing(&block)
      tries ||= 3
      yield
    rescue => e
      if retryable_exception?(e) && (tries -= 1) > 0
        sleep(rand * 5)
        retry
      else
        logger.warn "RETRY EXHAUSTED #{e.class} #{e.message.truncate(100)}"
        raise
      end
    end

    def self.retryable_exception?(ex)
      (ex.class == ActiveRecord::StatementInvalid && ex.message.start_with?('Mysql2::Error: Deadlock found when trying to get lock; try restarting transaction')) ||
          (ex.class == ActiveRecord::Deadlocked &&   ex.message.start_with?('Mysql2::Error: Deadlock found when trying to get lock; try restarting transaction')) ||
          ex.message.include?('Connection reset by peer')
    end
  end
end
