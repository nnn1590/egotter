class BlockingOrBlockedController < ::Page::Base
  include Concerns::UnfriendsConcern
  include TweetTextHelper

  def all
    initialize_instance_variables
    render template: 'friends/all' unless performed?
  end

  def show
    initialize_instance_variables
    @active_tab = 2
    render template: 'unfriends/show' unless performed?
  end
end
