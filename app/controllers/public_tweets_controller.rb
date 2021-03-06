class PublicTweetsController < ApplicationController

  before_action { self.access_log_disabled = true }

  def load
    keyword = 'えごったー 便利' # 'egotter OR えごったー OR #egotter'
    html = render_to_string partial: 'twitter/tweet', collection: fetch_tweets(keyword), cached: true

    # Avoid FrozenError can't modify frozen String
    html = html.gsub(/(便利)/) { %Q(<span class="egotter-pink">便利</span>) }
    html = html.gsub(/(えごったー)/) { %Q(<span class="egotter-pink">えごったー</span>) }
    render json: {html: html}
  end

  private

  def fetch_tweets(keyword)
    if ::Util::TweetsCache.exists?(keyword)
      CreateTweetsWorker.perform_async(keyword) if ::Util::TweetsCache.ttl(keyword) < 5.minutes
      JSON.parse(::Util::TweetsCache.get(keyword)).take(5).map { |tweet| Hashie::Mash.new(tweet) }
    else
      CreateTweetsWorker.perform_async(keyword)
      []
    end
  rescue => e
    logger.warn "#{__method__}: #{e.class} #{e.message} #{keyword}"
    notify_airbrake(e)
    []
  end
end
