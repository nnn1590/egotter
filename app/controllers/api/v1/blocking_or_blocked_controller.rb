module Api
  module V1
    class BlockingOrBlockedController < ::Api::V1::Base

      private

      def summary_uids(limit: SUMMARY_LIMIT)
        resources = @twitter_user.mutual_unfriendships
        [resources.limit(limit).pluck(:friend_uid), resources.size]
      end

      def list_users
        @twitter_user.mutual_unfriends
      end
    end
  end
end
