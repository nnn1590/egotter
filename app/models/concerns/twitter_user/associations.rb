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

    with_options({primary_key: :uid, foreign_key: :uid}.update(default_options)) do |obj|
      obj.has_many :statuses,  order_by_sequence_asc, class_name: 'TwitterDB::Status'
      obj.has_many :favorites, order_by_sequence_asc, class_name: 'TwitterDB::Favorite'
      obj.has_many :mentions,  order_by_sequence_asc, class_name: 'TwitterDB::Mention'
    end

    with_options({primary_key: :uid, foreign_key: :from_uid}.update(default_options)) do |obj|
      obj.has_many :one_sided_friendships,   order_by_sequence_asc
      obj.has_many :one_sided_followerships, order_by_sequence_asc
      obj.has_many :mutual_friendships,      order_by_sequence_asc

      obj.has_many :inactive_friendships,        order_by_sequence_asc
      obj.has_many :inactive_followerships,      order_by_sequence_asc
      obj.has_many :inactive_mutual_friendships, order_by_sequence_asc

      obj.has_many :favorite_friendships, order_by_sequence_asc
      obj.has_many :close_friendships,    order_by_sequence_asc
    end

    with_options({class_name: 'TwitterDB::User'}.update(default_options)) do |obj|
      obj.has_many :one_sided_friends,   through: :one_sided_friendships
      obj.has_many :one_sided_followers, through: :one_sided_followerships
      obj.has_many :mutual_friends,      through: :mutual_friendships

      obj.has_many :inactive_friends,        through: :inactive_friendships
      obj.has_many :inactive_followers,      through: :inactive_followerships
      obj.has_many :inactive_mutual_friends, through: :inactive_mutual_friendships

      obj.has_many :favorite_friends, through: :favorite_friendships
      obj.has_many :close_friends,    through: :close_friendships
    end

    with_options default_options.merge(primary_key: :uid, foreign_key: :from_uid) do |obj|
      obj.has_many :unfriendships,     order_by_sequence_asc
      obj.has_many :unfollowerships,   order_by_sequence_asc
    end

    with_options default_options.merge(class_name: 'TwitterDB::User') do |obj|
      obj.has_many :unfriends,     through: :unfriendships
      obj.has_many :unfollowers,   through: :unfollowerships
    end
  end

  def friends
    friend_uids = self.friend_uids
    TwitterDB::User.where(uid: friend_uids).sort_by {|user| friend_uids.index(user.uid)}
  end

  def followers
    follower_uids = self.follower_uids
    TwitterDB::User.where(uid: follower_uids).sort_by {|user| follower_uids.index(user.uid)}
  end
end
