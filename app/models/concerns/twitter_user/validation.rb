require 'active_support/concern'

module Concerns::TwitterUser::Validation
  extend ActiveSupport::Concern

  MANY_FRIENDS = Rails.configuration.x.constants['many_friends_threshold']
  TOO_MANY_FRIENDS = Rails.configuration.x.constants['too_many_friends_threshold']

  SCREEN_NAME_REGEXP = /\A[a-zA-Z0-9_]{1,20}\z/

  included do
    with_options on: :create do |obj|
      obj.validates :uid, presence: true, numericality: :only_integer
      obj.validates :screen_name, format: {with: SCREEN_NAME_REGEXP}
      obj.validates :user_info, presence: true

      obj.validate :unauthorized?
      obj.validate :suspended_account?
      obj.validate :inconsistent_friends?
      obj.validate :inconsistent_followers?
      obj.validate :zero_friends?
      obj.validate :too_many_friends?
      obj.validate :recently_created_record_exists?
      obj.validate :same_record_exists?
    end

    def invalid_screen_name?
      !(screen_name =~ SCREEN_NAME_REGEXP)
    end

    def anonymous_search?
      login_user.nil?
    end

    def ego_surfing?
      !anonymous_search? &&
      client.present? &&
        uid.to_i == login_user.uid.to_i &&
        uid.to_i == client.uid.to_i &&
        egotter_context == 'search'
    end

    def unauthorized?
      if user_info.blank?
        # call fetch_user before colling this method
        errors[:base] << 'user_info is blank'
        return true
      end

      return false unless protected

      # login_user is protected and search himself
      if egotter_context == 'search'
        if anonymous_search?
          errors[:base] << 'search protected user without login'
          return true
        end
        return false if ego_surfing?

        # TODO if this instance has followers, use follower_uids.include?(login_user.uid.to_i)
        if client.present?
          return false if client.friendship?(login_user.uid_i, uid.to_i) # login user follows searched user
        end

        true
      else
        # background job
        return false if User.exists?(uid: uid.to_i)

        errors[:base] << 'unauthorized worker'
        true
      end
    end

    def suspended_account?
      if suspended
        errors[:base] << 'suspended'
        return true
      end

      false
    end

    def inconsistent_friends?
      if friends_count.to_i != friends.size
        errors[:base] << "friends_count(#{friends_count}) != friends.size(#{friends.size})"
        return true
      end

      false
    end

    def inconsistent_followers?
      if followers_count.to_i != followers.size
        errors[:base] << "followers_count(#{followers_count}) != followers.size(#{followers.size})"
        return true
      end

      false
    end

    def zero_friends?
      if friends_count + followers_count <= 0
        errors[:base] << 'friends + followers == 0'
        return true
      end

      false
    end

    def too_many_friends?
      friends_limit =
        if egotter_context == 'search'
          login_user.nil? ? MANY_FRIENDS : TOO_MANY_FRIENDS
        else
          User.exists?(uid: uid.to_i) ? TOO_MANY_FRIENDS : MANY_FRIENDS
        end

      if friends_count + followers_count > friends_limit
        errors[:base] << "too many friends(#{friends_count}) and followers(#{followers_count})"
        return true
      end

      false
    end

    def recently_created_record_exists?
      me = latest_me
      return false if me.blank?

      if me.recently_created? || me.recently_updated?
        errors[:base] << 'recently created record exists'
        return true
      end

      false
    end

    def same_record_exists?
      same_record?(latest_me)
    end

    def same_record?(tu)
      return false if tu.blank?
      raise "uid is different(#{self.uid},#{tu.uid})" if self.uid.to_i != tu.uid.to_i

      if self.friends_count != tu.friends_count
        logger.debug "#{screen_name} friends_count is different(#{self.friends_count}, #{tu.friends_count})"
        return false
      end

      if self.followers_count != tu.followers_count
        logger.debug "#{screen_name} followers_count is different(#{self.followers_count}, #{tu.followers_count})"
        return false
      end

      if self.friend_uids != tu.friend_uids
        logger.debug "#{screen_name} friend_uids is different(#{self.friend_uids}, #{tu.friend_uids})"
        return false
      end

      if self.follower_uids != tu.follower_uids
        logger.debug "#{screen_name} follower_uids is different(#{self.follower_uids}, #{tu.follower_uids})"
        return false
      end

      errors[:base] << "id:#{tu.id} is the same record"
      true
    end
  end
end