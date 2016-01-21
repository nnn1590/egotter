# == Schema Information
#
# Table name: followers
#
#  id          :integer          not null, primary key
#  uid         :string(255)      not null
#  screen_name :string(255)      not null
#  user_info   :text(65535)      not null
#  from_id     :integer          not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  index_followers_on_screen_name  (screen_name)
#  index_followers_on_uid          (uid)
#

class Follower < ActiveRecord::Base
  belongs_to :twitter_user

  delegate *TwitterUser::SAVE_KEYS.reject { |k| k.in?(%i(id screen_name)) }, to: :user_info_mash

  def user_info_mash
    @user_info_hash ||= Hashie::Mash.new(JSON.parse(user_info))
  end

  def eql?(other)
    self.uid.to_i == other.uid.to_i
  end

  def hash
    self.uid.to_i.hash
  end
end
