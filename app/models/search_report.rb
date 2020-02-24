# == Schema Information
#
# Table name: search_reports
#
#  id         :bigint(8)        not null, primary key
#  user_id    :integer          not null
#  read_at    :datetime
#  message_id :string(191)      not null
#  message    :string(191)      default(""), not null
#  token      :string(191)      not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_search_reports_on_created_at  (created_at)
#  index_search_reports_on_token       (token) UNIQUE
#  index_search_reports_on_user_id     (user_id)
#

class SearchReport < ApplicationRecord
  include Concerns::Report::HasToken
  include Concerns::Report::HasDirectMessage
  include Concerns::Report::Readable

  belongs_to :user

  attr_accessor :searcher_uid

  def self.you_are_searched(searchee_id, searcher_uid = nil)
    new(user_id: searchee_id, token: generate_token, searcher_uid: searcher_uid)
  end

  def deliver!
    dm = User.egotter.api_client.create_direct_message_event(user.uid, report_message)

    transaction do
      update!(message_id: dm.id, message: dm.truncated_message)
      user.notification_setting.update!(search_sent_at: Time.zone.now)
    end

    dm
  end

  private

  def start_message
    template = Rails.root.join('app/views/search_reports/start.ja.text.erb')
    ERB.new(template.read).result_with_hash(screen_name: user.screen_name)
  end

  def report_message
    relationship =
        if (searchee = TwitterUser.latest_by(uid: user.uid))
          is_following = searchee.friend_uids.include?(searcher_uid)
          is_follower = searchee.follower_uids.include?(searcher_uid)
          I18n.t("dm.searchNotification.relationship.#{is_following}.#{is_follower}", user: user.screen_name)
        else
          I18n.t('dm.searchNotification.relationship.none')
        end

    template = Rails.root.join('app/views/search_reports/you_are_searched.ja.text.erb')
    ERB.new(template.read).result_with_hash(
        screen_name: user.screen_name,
        relationship: relationship,
        settings_url: Rails.application.routes.url_helpers.settings_url(via: 'search_report', og_tag: 'false')
    )
    end

    def timeline_url
      Rails.application.routes.url_helpers.timeline_url(screen_name: user.screen_name, token: token, medium: 'dm', type: 'search', via: 'search_report', og_tag: 'false')
    end
  end
