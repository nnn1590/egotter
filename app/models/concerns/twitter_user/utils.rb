require 'active_support/concern'

module Concerns::TwitterUser::Utils
  extend ActiveSupport::Concern

  class_methods do
    def latest(uid)
      order(created_at: :desc).find_by(uid: uid.to_i)
    end
  end

  DEFAULT_SECONDS = Rails.configuration.x.constants['twitter_user_recently_created']

  included do
  end

  def mention_name
    "@#{screen_name}"
  end

  def friend_uids
    new_record? ? friends.map { |f| f.uid.to_i } : friends.pluck(:uid).map { |uid| uid.to_i }
  end

  def follower_uids
    new_record? ? followers.map { |f| f.uid.to_i } : followers.pluck(:uid).map { |uid| uid.to_i }
  end

  def fresh?(seconds = DEFAULT_SECONDS)
    Time.zone.now - updated_at < seconds
  end

  def search_and_touch
    update!(search_count: search_count + 1)
  rescue => e
    logger.error "#{self.class}##{__method__}: #{e.class} #{e.message}"
  end

  def update_and_touch
    update!(update_count: update_count + 1)
  rescue => e
    logger.error "#{self.class}##{__method__}: #{e.class} #{e.message}"
  end
end