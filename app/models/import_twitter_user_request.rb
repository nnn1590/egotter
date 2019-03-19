# == Schema Information
#
# Table name: import_twitter_user_requests
#
#  id              :bigint(8)        not null, primary key
#  user_id         :integer          not null
#  twitter_user_id :integer          not null
#  finished_at     :datetime
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
# Indexes
#
#  index_import_twitter_user_requests_on_created_at  (created_at)
#  index_import_twitter_user_requests_on_user_id     (user_id)
#

class ImportTwitterUserRequest < ApplicationRecord
  include Concerns::Request::Runnable
  belongs_to :user, optional: true
  belongs_to :twitter_user

  validates :user_id, presence: true
  validates :twitter_user_id, presence: true

  def perform!
    import_favorite_friendship
    import_close_friendship

    return if twitter_user.no_need_to_import_friendships?

    import_twitter_db_users

    [
        Unfriendship,
        Unfollowership,
        OneSidedFriendship,
        OneSidedFollowership,
        MutualFriendship,
        BlockFriendship,
        InactiveFriendship,
        InactiveFollowership,
        InactiveMutualFriendship,
    ].each do |klass|
      klass.import_by!(twitter_user: twitter_user)
    rescue => e
      logger.warn "#{klass} #{e.class} #{e.message.truncate(100)} #{twitter_user.id}"
      logger.info e.backtrace.join("\n")
    end
  end

  def perform
    perform!
  rescue => e
    logger.warn "#{self.class}##{__method__} #{e.class} #{e.message} #{self.inspect}"
    logger.info e.backtrace.join("\n")
  end

  def import_favorite_friendship
    uids = FavoriteFriendship.import_by(twitter_user: twitter_user)
    TwitterDB::User::Batch.fetch_and_import!(uids, client: client)
  rescue => e
    logger.warn "#{__method__} #{e.class} #{e.message.truncate(100)} #{twitter_user.id}"
    logger.info e.backtrace.join("\n")
  end

  def import_close_friendship
    uids = CloseFriendship.import_by(twitter_user: twitter_user, login_user: user)
    TwitterDB::User::Batch.fetch_and_import!(uids, client: client)
  rescue => e
    logger.warn "#{__method__} #{e.class} #{e.message.truncate(100)} #{twitter_user.id}"
    logger.info e.backtrace.join("\n")
  end

  def import_twitter_db_users
    uids = [twitter_user.uid] + twitter_user.friend_uids + twitter_user.follower_uids
    TwitterDB::User::Batch.fetch_and_import!(uids, client: client)
  rescue => e
    logger.warn "#{__method__} #{e.class} #{e.message.truncate(100)} #{twitter_user.id}"
    logger.info e.backtrace.join("\n")
  end

  def client
    if instance_variable_defined?(:@client)
      @client
    else
      @client = user ? user.api_client : Bot.api_client
    end
  end
end
