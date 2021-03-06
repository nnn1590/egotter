require 'twitter'

# It is necessary to load the classes first because they may be called in Thread.
require_relative '../../app/models/call_create_friendship_count'
require_relative '../../app/models/call_user_timeline_count'
require_relative '../../app/models/call_create_direct_message_event_count'

module Egotter
  module Twitter
    module Measurement
      def follow!(*args)
        super
      ensure
        CallCreateFriendshipCount.new.increment
      end

      def user_timeline(*args)
        super
      ensure
        CallUserTimelineCount.new.increment
      end

      def create_direct_message_event(*args)
        recipient_uid = dig_recipient_uid(args)

        if !GlobalDirectMessageReceivedFlag.new.exists?(recipient_uid) &&
            GlobalDirectMessageLimitation.new.limited?
          raise ::Twitter::Error::EnhanceYourCalm.new('Already raised')
        end

        result = nil
        begin
          result = super
        rescue ::Twitter::Error::EnhanceYourCalm => e
          GlobalDirectMessageLimitation.new.limit_start
          raise
        else
          set_global_direct_message_flags(recipient_uid)
        end

        result
      end

      def set_global_direct_message_flags(recipient_uid)
        # TODO Remove later
        CallCreateDirectMessageEventCount.new.increment

        GlobalSendDirectMessageCount.new.increment
        if recipient_uid != User::EGOTTER_UID
          GlobalSendDirectMessageFromEgotterCount.new.increment
          GlobalSendDirectMessageCountByUser.new.increment(recipient_uid)
        end

        if GlobalDirectMessageReceivedFlag.new.exists?(recipient_uid)
          GlobalPassiveSendDirectMessageCount.new.increment

          if recipient_uid != User::EGOTTER_UID
            GlobalPassiveSendDirectMessageFromEgotterCount.new.increment
          end
        else
          GlobalActiveSendDirectMessageCount.new.increment

          if recipient_uid != User::EGOTTER_UID
            GlobalActiveSendDirectMessageFromEgotterCount.new.increment
          end
        end

      rescue => e
        Rails.logger.warn "counting in #{__method__} #{e.inspect}"
      end

      def dig_recipient_uid(args)
        if args.length == 1 && args.last.is_a?(Hash)
          args.last.dig(:event, :message_create, :target, :recipient_id)
        elsif args.length == 2 && args.first.is_a?(Integer)
          args.first
        else
          nil
        end
      end
    end
  end
end

::Twitter::REST::Client.prepend(::Egotter::Twitter::Measurement)
