# == Schema Information
#
# Table name: block_friendships
#
#  id         :bigint(8)        not null, primary key
#  from_uid   :bigint(8)        not null
#  friend_uid :bigint(8)        not null
#  sequence   :integer          not null
#
# Indexes
#
#  index_block_friendships_on_friend_uid  (friend_uid)
#  index_block_friendships_on_from_uid    (from_uid)
#

class BlockFriendship < ApplicationRecord
  include Concerns::Friendship::Importable

  with_options(primary_key: :uid, optional: true) do |obj|
    obj.belongs_to :twitter_user, foreign_key: :from_uid
    obj.belongs_to :block_friend, foreign_key: :friend_uid, class_name: 'TwitterDB::User'
  end

  class << self
    def import_by!(twitter_user:)
      uids = twitter_user.calc_mutual_unfriend_uids
      import_from!(twitter_user.uid, uids)
      uids
    end
  end
end
