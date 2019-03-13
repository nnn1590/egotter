# == Schema Information
#
# Table name: search_histories
#
#  id         :integer          not null, primary key
#  session_id :string(191)      default(""), not null
#  user_id    :integer          not null
#  uid        :bigint(8)        not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_search_histories_on_created_at  (created_at)
#  index_search_histories_on_session_id  (session_id)
#  index_search_histories_on_user_id     (user_id)
#

class SearchHistory < ApplicationRecord
  belongs_to :user, optional: true
  has_one :twitter_db_user, primary_key: :uid, foreign_key: :uid, class_name: 'TwitterDB::User'

  validates :user_id, numericality: {only_integer: true}
  validates :session_id, format: {with: /\A.+\w+.+\Z/}

  def to_param
    screen_name
  end

  delegate(
    *%i(
      uid
      screen_name
      name
      friends_count
      followers_count
      statuses_count
      description
      profile_image_url_https
      protected
      verified
      suspended
      inactive
      status
    ),
    to: :twitter_db_user,
    allow_nil: true
  )

  def referral(session_id)
    logs =
        SearchLog.select(:referer).
            where(created_at: 30.minutes.ago..Time.zone.now).
            where(session_id: session_id).
            where.not(referer: ['', nil]).
            order(created_at: :desc)

    url =
        logs.pluck(:referer).find do |ref|
          ref.present? &&
              ref.match?(URI.regexp) &&
              URI.parse(ref).host.exclude?('egotter')
        end

    url.blank? ? '' : URI.parse(url).host

    case url
    when 't.co' then 'twitter'
    else url
    end
  end
end
