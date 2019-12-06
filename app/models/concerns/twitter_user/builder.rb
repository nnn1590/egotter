require 'active_support/concern'

module Concerns::TwitterUser::Builder
  extend ActiveSupport::Concern
  include Concerns::TwitterUser::AssociationBuilder

  class_methods do
    def build_by(user:)
      TwitterUser.new(
          uid: user[:id],
          screen_name: user[:screen_name],
          friends_count: user[:friends_count],
          followers_count: user[:followers_count],
          raw_attrs_text: TwitterUser.collect_user_info(user)
      )
    end
  end
end
