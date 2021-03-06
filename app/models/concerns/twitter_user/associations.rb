require 'active_support/concern'

module Concerns::TwitterUser::Associations
  extend ActiveSupport::Concern

  class_methods do
  end

  included do
    with_options(optional: true) do |obj|
      obj.belongs_to :user
      obj.belongs_to :twitter_db_user, primary_key: :uid, foreign_key: :uid, class_name: 'TwitterDB::User'
    end

    default_options = {dependent: :destroy, validate: false, autosave: false}
    order_by_sequence_asc = -> { order(sequence: :asc) }

    with_options({primary_key: :uid, foreign_key: :uid}.update(default_options)) do |obj|
      obj.has_one :usage_stat
      obj.has_one :score
    end

    with_options({primary_key: :uid, foreign_key: :from_uid}.update(default_options)) do |obj|
      # obj.has_many :one_sided_friendships,       order_by_sequence_asc
      # obj.has_many :one_sided_followerships,     order_by_sequence_asc
      # obj.has_many :mutual_friendships,          order_by_sequence_asc

      # obj.has_many :inactive_friendships,        order_by_sequence_asc
      # obj.has_many :inactive_followerships,      order_by_sequence_asc
      # obj.has_many :inactive_mutual_friendships, order_by_sequence_asc

      obj.has_many :favorite_friendships,        order_by_sequence_asc
      obj.has_many :close_friendships,           order_by_sequence_asc
    end

    with_options({class_name: 'TwitterDB::User'}.update(default_options)) do |obj|
      # obj.has_many :one_sided_friends,       through: :one_sided_friendships
      # obj.has_many :one_sided_followers,     through: :one_sided_followerships
      # obj.has_many :mutual_friends,          through: :mutual_friendships

      # obj.has_many :inactive_friends,        through: :inactive_friendships
      # obj.has_many :inactive_followers,      through: :inactive_followerships
      # obj.has_many :inactive_mutual_friends, through: :inactive_mutual_friendships

      obj.has_many :favorite_friends,        through: :favorite_friendships
      obj.has_many :close_friends,           through: :close_friendships
    end
  end

  class RelationshipProxy
    def initialize(data)
      @data = data
      @limit = nil
    end

    def size
      @data.uids.size
    end

    def limit(count)
      @limit = count
      self
    end

    def pluck(*args)
      if @limit
        @data.uids.take(@limit)
      else
        @data.uids
      end
    end
  end

  def mutual_friendships
    if (from_s3 = S3::MutualFriendship.where(uid: uid))
      RelationshipProxy.new(from_s3)
    else
      MutualFriendship.where(from_uid: uid).order(sequence: :asc)
    end
  end

  def one_sided_friendships
    if (from_s3 = S3::OneSidedFriendship.where(uid: uid))
      RelationshipProxy.new(from_s3)
    else
      OneSidedFriendship.where(from_uid: uid).order(sequence: :asc)
    end
  end

  def one_sided_followerships
    if (from_s3 = S3::OneSidedFollowership.where(uid: uid))
      RelationshipProxy.new(from_s3)
    else
      OneSidedFollowership.where(from_uid: uid).order(sequence: :asc)
    end
  end

  def inactive_friendships
    if (from_s3 = S3::InactiveFriendship.where(uid: uid))
      RelationshipProxy.new(from_s3)
    else
      InactiveFriendship.where(from_uid: uid).order(sequence: :asc)
    end
  end

  def inactive_followerships
    if (from_s3 = S3::InactiveFollowership.where(uid: uid))
      RelationshipProxy.new(from_s3)
    else
      InactiveFollowership.where(from_uid: uid).order(sequence: :asc)
    end
  end

  def inactive_mutual_friendships
    if (from_s3 = S3::InactiveMutualFriendship.where(uid: uid))
      RelationshipProxy.new(from_s3)
    else
      InactiveMutualFriendship.where(from_uid: uid).order(sequence: :asc)
    end
  end

  def mutual_unfriendships
    if (from_s3 = S3::MutualUnfriendship.where(uid: uid))
      RelationshipProxy.new(from_s3)
    else
      BlockFriendship.where(from_uid: uid).order(sequence: :asc)
    end
  end

  def unfriendships
    if (from_s3 = S3::Unfriendship.where(uid: uid))
      RelationshipProxy.new(from_s3)
    else
      Unfriendship.where(from_uid: uid).order(sequence: :asc)
    end
  end

  def unfollowerships
    if (from_s3 = S3::Unfollowership.where(uid: uid))
      RelationshipProxy.new(from_s3)
    else
      Unfollowership.where(from_uid: uid).order(sequence: :asc)
    end
  end

  FETCH_USERS_LIMIT = 10000

  def mutual_friends(limit: FETCH_USERS_LIMIT, inactive: nil)
    TwitterDB::User.where_and_order_by_field(uids: mutual_friend_uids.take(limit), inactive: inactive)
  end

  def one_sided_friends(limit: FETCH_USERS_LIMIT)
    TwitterDB::User.where_and_order_by_field(uids: one_sided_friend_uids.take(limit))
  end

  def one_sided_followers(limit: FETCH_USERS_LIMIT)
    TwitterDB::User.where_and_order_by_field(uids: one_sided_follower_uids.take(limit))
  end

  def inactive_friends(limit: FETCH_USERS_LIMIT)
    TwitterDB::User.where_and_order_by_field(uids: inactive_friend_uids.take(limit))
  end

  def inactive_followers(limit: FETCH_USERS_LIMIT)
    TwitterDB::User.where_and_order_by_field(uids: inactive_follower_uids.take(limit))
  end

  def inactive_mutual_friends(limit: FETCH_USERS_LIMIT)
    TwitterDB::User.where_and_order_by_field(uids: inactive_mutual_friend_uids.take(limit))
  end

  def friends(limit: FETCH_USERS_LIMIT, inactive: nil)
    TwitterDB::User.where_and_order_by_field(uids: friend_uids.take(limit), inactive: inactive)
  end

  def followers(limit: FETCH_USERS_LIMIT, inactive: nil)
    TwitterDB::User.where_and_order_by_field(uids: follower_uids.take(limit), inactive: inactive)
  end

  def mutual_unfriends(limit: FETCH_USERS_LIMIT)
    TwitterDB::User.where_and_order_by_field(uids: mutual_unfriend_uids.take(limit))
  end

  def unfriends(limit: FETCH_USERS_LIMIT)
    TwitterDB::User.where_and_order_by_field(uids: unfriend_uids.take(limit))
  end

  def unfollowers(limit: FETCH_USERS_LIMIT)
    TwitterDB::User.where_and_order_by_field(uids: unfollower_uids.take(limit))
  end

  def mutual_friend_uids
    mutual_friendships.pluck(:friend_uid)
  end

  def one_sided_friend_uids
    one_sided_friendships.pluck(:friend_uid)
  end

  def one_sided_follower_uids
    one_sided_followerships.pluck(:follower_uid)
  end

  def inactive_mutual_friend_uids
    inactive_mutual_friendships.pluck(:friend_uid)
  end

  def inactive_friend_uids
    inactive_friendships.pluck(:friend_uid)
  end

  def inactive_follower_uids
    inactive_followerships.pluck(:follower_uid)
  end

  def mutual_unfriend_uids
    mutual_unfriendships.pluck(:friend_uid)
  end

  def unfriend_uids
    unfriendships.pluck(:friend_uid)
  end

  def unfollower_uids
    unfollowerships.pluck(:follower_uid)
  end

  # TODO Return an instance of Efs::StatusTweet or S3::StatusTweet
  def status_tweets
    logger.debug { "#{__method__} is called twitter_user_id=#{id}" }
    tweets = []
    tweets = InMemory::StatusTweet.find_by(uid) if InMemory.enabled? && InMemory.cache_alive?(created_at)
    tweets = Efs::StatusTweet.where(uid: uid) if tweets.blank? && Efs::Tweet.cache_alive?(created_at)
    tweets = ::S3::StatusTweet.where(uid: uid) if tweets.blank?
    tweets.map { |tweet| ::TwitterDB::Status.new(uid: uid, screen_name: screen_name, raw_attrs_text: tweet.raw_attrs_text) }
  end

  # TODO Return an instance of Efs::FavoriteTweet or S3::FavoriteTweet
  def favorite_tweets
    logger.debug { "#{__method__} is called twitter_user_id=#{id}" }
    tweets = []
    tweets = InMemory::FavoriteTweet.find_by(uid) if InMemory.enabled? && InMemory.cache_alive?(created_at)
    tweets = Efs::FavoriteTweet.where(uid: uid) if tweets.blank? && Efs::Tweet.cache_alive?(created_at)
    tweets = ::S3::FavoriteTweet.where(uid: uid) if tweets.blank?
    tweets.map { |tweet| ::TwitterDB::Favorite.new(uid: uid, screen_name: screen_name, raw_attrs_text: tweet.raw_attrs_text) }
  end

  # TODO Return an instance of Efs::MentionTweet or S3::MentionTweet
  def mention_tweets
    logger.debug { "#{__method__} is called twitter_user_id=#{id}" }
    tweets = []
    tweets = InMemory::MentionTweet.find_by(uid) if InMemory.enabled? && InMemory.cache_alive?(created_at)
    tweets = Efs::MentionTweet.where(uid: uid) if tweets.blank? && Efs::Tweet.cache_alive?(created_at)
    tweets = ::S3::MentionTweet.where(uid: uid) if tweets.blank?
    tweets.map { |tweet| ::TwitterDB::Mention.new(uid: uid, screen_name: screen_name, raw_attrs_text: tweet.raw_attrs_text) }
  end

  def users_by(controller_name:, limit: 300)
    users = send(controller_name)
    users.is_a?(Array) ? users.take(limit) : users.limit(limit)
  end

  def common_users_by(controller_name:, friend:, limit: 300)
    send(controller_name, friend).take(limit)
  end
end
