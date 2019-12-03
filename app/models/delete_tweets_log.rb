# == Schema Information
#
# Table name: delete_tweets_logs
#
#  id            :integer          not null, primary key
#  user_id       :integer          default(-1), not null
#  request_id    :integer          default(-1), not null
#  status        :boolean          default(FALSE), not null
#  destroy_count :integer          default(0), not null
#  retry_in      :integer          default(0), not null
#  message       :string(191)      default(""), not null
#  error_class   :string(191)      default(""), not null
#  error_message :string(191)      default(""), not null
#  created_at    :datetime         not null
#
# Indexes
#
#  index_delete_tweets_logs_on_created_at  (created_at)
#

class DeleteTweetsLog < ApplicationRecord
  include Concerns::Log::Runnable

  before_validation do
    if self.error_message
      self.error_message = self.error_message.truncate(150)
    end

    if self.message
      self.message = self.message.truncate(150)
    end
  end

  class << self
    def create_by(request:)
      create(
          user_id: request.user.id,
          request_id: request.id,
      )
    end
  end
end
