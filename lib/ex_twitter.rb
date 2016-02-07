require 'active_support'
require 'active_support/cache'

require 'twitter'
require 'memoist'
require 'parallel'



class ExTwitter < Twitter::REST::Client
  extend Memoist

  def initialize(options = {})
    @cache = ActiveSupport::Cache::FileStore.new(File.join('tmp', 'api_cache', Time.now.strftime('%Y%m%d%H')))
    @uid = options[:uid]
    @screen_name = options[:screen_name]
    super
  end

  attr_reader :cache, :uid, :screen_name

  def logger
    @logger ||= Logger.new('log/ex_twitter.log')
  end

  def call_old_method(method_name, *args)
    options = args.extract_options!
    begin
      start_t = Time.now
      result = send(method_name, *args, options)
      end_t = Time.now
      logger.debug "#{method_name} #{args.inspect} #{options.inspect} (#{end_t - start_t}s)"
      result
    rescue Twitter::Error::TooManyRequests => e
      logger.warn "#{__method__}: call=#{method_name} #{args.inspect} #{e.class} Retry after #{e.rate_limit.reset_in} seconds."
      raise e
    rescue Twitter::Error::ServiceUnavailable => e
      logger.warn "#{__method__}: call=#{method_name} #{args.inspect} #{e.class} #{e.message}"
      raise e
    rescue Twitter::Error::InternalServerError => e
      logger.warn "#{__method__}: call=#{method_name} #{args.inspect} #{e.class} #{e.message}"
      raise e
    rescue Twitter::Error::Forbidden => e
      logger.warn "#{__method__}: call=#{method_name} #{args.inspect} #{e.class} #{e.message}"
      raise e
    rescue Twitter::Error::NotFound => e
      logger.warn "#{__method__}: call=#{method_name} #{args.inspect} #{e.class} #{e.message}"
      raise e
    rescue => e
      logger.warn "#{__method__}: call=#{method_name} #{args.inspect} #{e.class} #{e.message}"
      raise e
    end
  end

  # user_timeline, search
  def collect_with_max_id(method_name, *args)
    options = args.extract_options!
    options[:call_count] = 3 unless options.has_key?(:call_count)
    last_response = call_old_method(method_name, *args, options)
    last_response = yield(last_response) if block_given?
    return_data = last_response
    call_count = 1

    while last_response.any? && call_count < options[:call_count]
      options[:max_id] = last_response.last.kind_of?(Hash) ? last_response.last[:id] : last_response.last.id
      last_response = call_old_method(method_name, *args, options)
      last_response = yield(last_response) if block_given?
      return_data += last_response
      call_count += 1
    end

    return_data.flatten
  end

  # friends, followers
  def collect_with_cursor(method_name, *args)
    options = args.extract_options!
    last_response = call_old_method(method_name, *args, options).attrs
    return_data = (last_response[:users] || last_response[:ids])

    while (next_cursor = last_response[:next_cursor]) && next_cursor != 0
      options[:cursor] = next_cursor
      last_response = call_old_method(method_name, *args, options).attrs
      return_data += (last_response[:users] || last_response[:ids])
    end

    return_data
  end

  require 'digest/md5'

  # currently ignore options
  def file_cache_key(method_name, user)
    delim = ':'
    identifier =
      case
        when method_name == :search
          "str#{delim}#{user.to_s}"
        when method_name == :mentions_timeline
          "myself#{delim}#{user.to_s}"
        when method_name == :home_timeline
          "myself#{delim}#{user.to_s}"
        when user.kind_of?(Integer)
          "id#{delim}#{user.to_s}"
        when user.kind_of?(Array) && user.first.kind_of?(Integer)
          "ids#{delim}#{Digest::MD5.hexdigest(user.join(','))}"
        when user.kind_of?(Array) && user.first.kind_of?(String)
          "sns#{delim}#{Digest::MD5.hexdigest(user.join(','))}"
        when user.kind_of?(String)
          "sn#{delim}#{user}"
        when user.kind_of?(Twitter::User)
          "user#{delim}#{user.id.to_s}"
        else raise "#{method_name.inspect} #{user.inspect}"
      end

    "#{method_name}#{delim}#{identifier}"
  end

  def namespaced_key(method_name, user)
    file_cache_key(method_name, user)
  end

  # encode
  def encode_json(obj, caller_name, options = {})
    options[:reduce] = true unless options.has_key?(:reduce)
    start_t = Time.now
    result =
      case caller_name
        when :user_timeline, :home_timeline, :mentions_timeline, :favorites # Twitter::Tweet
          JSON.pretty_generate(obj.map { |o| o.attrs })

        when :search # Hash
          data =
            if options[:reduce]
              obj.map { |o| o.to_hash.slice(*Status::STATUS_SAVE_KEYS) }
            else
              obj.map { |o| o.to_hash }
            end
          JSON.pretty_generate(data)

        when :friends, :followers # Hash
          data =
            if options[:reduce]
              obj.map { |o| o.to_hash.slice(*TwitterUser::PROFILE_SAVE_KEYS) }
            else
              obj.map { |o| o.to_hash }
            end
          JSON.pretty_generate(data)

        when :friend_ids, :follower_ids # Integer
          JSON.pretty_generate(obj)

        when :user # Twitter::User
          JSON.pretty_generate(obj.to_hash.slice(*TwitterUser::PROFILE_SAVE_KEYS))

        when :users, :friends_advanced, :followers_advanced # Twitter::User
          data =
            if options[:reduce]
              obj.map { |o| o.to_hash.slice(*TwitterUser::PROFILE_SAVE_KEYS) }
            else
              obj.map { |o| o.to_hash }
            end
          JSON.pretty_generate(data)

        when :user? # true or false
          obj

        when :friendship? # true or false
          obj

        # when obj.kind_of?(Array) && obj.empty?
        #   JSON.pretty_generate(obj)

        else
          raise "#{__method__}: caller=#{caller_name} key=#{options[:key]} obj=#{obj.inspect}"
      end
    end_t = Time.now
    logger.debug "#{__method__}: caller=#{caller_name} key=#{options[:key]} (#{end_t - start_t}s)"
    result
  end

  # decode
  def decode_json(json_str, caller_name, options = {})
    start_t = Time.now
    obj = json_str.kind_of?(String) ? JSON.parse(json_str) : json_str
    result =
      case
        when obj.kind_of?(Array) && obj.first.kind_of?(Hash)
          obj.map { |o| Hashie::Mash.new(o) }

        when obj.kind_of?(Array) && obj.first.kind_of?(Integer)
          obj

        when obj.kind_of?(Hash)
          Hashie::Mash.new(obj)

        when obj === true || obj === false
          obj

        when obj.kind_of?(Array) && obj.empty?
          obj

        else
          raise "#{__method__}: caller=#{caller_name} key=#{options[:key]} obj=#{obj.inspect}"
      end
    end_t = Time.now
    logger.debug "#{__method__}: caller=#{caller_name} key=#{options[:key]} (#{end_t - start_t}s)"
    result
  end

  # options {cache: :force}
  def fetch_cache_or_call_api(method_name, user, options = {})
    start_t = Time.now
    key = namespaced_key(method_name, user)
    options.update(key: key)

    if cache.exist?(key)
      data = decode_json(cache.read(key), method_name, options)
      end_t = Time.now
      logger.debug "#{__method__}: caller=#{method_name} key=#{key} (cache read) (#{end_t - start_t}s)"
      return data
    end

    raise "#{__method__}: must use cache caller=#{method_name} key=#{key}" if options[:cache] == :force

    data = yield

    cache.write(key, encode_json(data, method_name, options))
    end_t = Time.now
    logger.debug "#{__method__}: caller=#{method_name} key=#{key} (cache wrote) (#{end_t - start_t}s)"

    data
  end

  alias :old_friendship? :friendship?
  def friendship?(*args)
    options = args.extract_options!
    fetch_cache_or_call_api(:friendship?, args) {
      call_old_method(:old_friendship?, *args, options)
    }
  end

  alias :old_user? :user?
  def user?(*args)
    raise 'this method needs at least one param to use cache' if args.empty?
    options = args.extract_options!
    fetch_cache_or_call_api(:user?, args[0], options) {
      call_old_method(:old_user?, args[0], options)
    }
  end

  alias :old_user :user
  def user(*args)
    raise 'this method needs at least one param to use cache' if args.empty?
    options = args.extract_options!
    fetch_cache_or_call_api(:user, args[0], options) {
      call_old_method(:old_user, args[0], options)
    }
  end
  # memoize :user

  alias :old_friend_ids :friend_ids
  def friend_ids(*args)
    raise 'this method needs at least one param to use cache' if args.empty?
    options = args.extract_options!
    fetch_cache_or_call_api(:friend_ids, args[0], options) {
      options = {count: 5000, cursor: -1}.merge(options)
      collect_with_cursor(:old_friend_ids, *args, options)
    }
  end

  alias :old_follower_ids :follower_ids
  def follower_ids(*args)
    raise 'this method needs at least one param to use cache' if args.empty?
    options = args.extract_options!
    fetch_cache_or_call_api(:follower_ids, args[0], options) {
      options = {count: 5000, cursor: -1}.merge(options)
      collect_with_cursor(:old_follower_ids, *args, options)
    }
  end

  # specify reduce: false to use tweet for inactive_*
  alias :old_friends :friends
  def friends(*args)
    raise 'this method needs at least one param to use cache' if args.empty?
    options = args.extract_options!
    options[:reduce] = false unless options.has_key?(:reduce)
    fetch_cache_or_call_api(:friends, args[0], options) {
      options = {count: 200, include_user_entities: true, cursor: -1}.merge(options)
      collect_with_cursor(:old_friends, *args, options)
    }
  end
  # memoize :friends

  def friends_advanced(*args)
    options = args.extract_options!
    _friend_ids = friend_ids(*(args + [options]))
    users(_friend_ids.map { |id| id.to_i }, options)
  end

  # specify reduce: false to use tweet for inactive_*
  alias :old_followers :followers
  def followers(*args)
    raise 'this method needs at least one param to use cache' if args.empty?
    options = args.extract_options!
    options[:reduce] = false unless options.has_key?(:reduce)
    fetch_cache_or_call_api(:followers, args[0], options) {
      options = {count: 200, include_user_entities: true, cursor: -1}.merge(options)
      collect_with_cursor(:old_followers, *args, options)
    }
  end
  # memoize :followers

  def followers_advanced(*args)
    options = args.extract_options!
    _follower_ids = follower_ids(*(args + [options]))
    users(_follower_ids.map { |id| id.to_i }, options)
  end

  def fetch_parallelly(signatures) # [{method: :friends, args: ['ts_3156', ...], {...}]
    result = Array.new(signatures.size)

    Parallel.each_with_index(signatures, in_threads: result.size) do |signature, i|
      result[i] = send(signature[:method], *signature[:args])
    end

    result
  end

  def friends_and_followers(*args)
    fetch_parallelly(
      [
        {method: 'friends_advanced', args: args},
        {method: 'followers_advanced', args: args}])
  end

  def friends_followers_and_statuses(*args)
    fetch_parallelly(
      [
        {method: 'friends_advanced', args: args},
        {method: 'followers_advanced', args: args},
        {method: 'user_timeline', args: args}])
  end

  def one_sided_following(me)
    me.friends.to_a - me.followers.to_a
  end

  def one_sided_followers(me)
    me.followers.to_a - me.friends.to_a
  end

  def mutual_friends(me)
    me.friends.to_a & me.followers.to_a
  end
  
  def common_friends(me, you)
    me.friends.to_a & you.friends.to_a
  end

  def common_followers(me, you)
    me.followers.to_a & you.followers.to_a
  end

  def removing(pre_me, cur_me)
    pre_me.friends.to_a - cur_me.friends.to_a
  end

  def detailed_removing(pre_me, cur_me)
  end

  def removed(pre_me, cur_me)
    pre_me.followers.to_a - cur_me.followers.to_a
  end

  def detailed_removed(pre_me, cur_me)
  end

  # use compact, not use sort and uniq
  # specify reduce: false to use tweet for inactive_*
  alias :old_users :users
  def users(*args)
    options = args.extract_options!
    users_per_workers = args.first.compact.each_slice(100).to_a
    processed_users = []

    Parallel.each_with_index(users_per_workers, in_threads: [users_per_workers.size, 10].min) do |users_per_worker, i|
      _users = fetch_cache_or_call_api(:users, users_per_worker, reduce: false) {
        call_old_method(:old_users, users_per_worker, options)
      }

      result = {i: i, users: _users}
      processed_users << result
    end

    processed_users.sort_by{|p| p[:i] }.map{|p| p[:users] }.flatten.compact
  end

  def called_by_authenticated_user?(user)
    authenticated_user = self.old_user
    if user.kind_of?(String)
      authenticated_user.screen_name == user
    elsif user.kind_of?(Integer)
      authenticated_user.id.to_i == user
    else
      raise user.inspect
    end
  end

  # can't get tweets if you are not authenticated by specified user
  alias :old_home_timeline :home_timeline
  def home_timeline(*args)
    raise 'this method needs at least one param to use cache' if args.empty?
    raise 'this method must be called by authenticated user' unless called_by_authenticated_user?(args[0])
    fetch_cache_or_call_api(:home_timeline, args[0]) {
      options = {count: 200, include_rts: true, call_count: 3}.merge(args.extract_options!)
      collect_with_max_id(:old_home_timeline, options)
    }
  end

  # can't get tweets if you are not authenticated by specified user
  alias :old_user_timeline :user_timeline
  def user_timeline(*args)
    raise 'this method needs at least one param to use cache' if args.empty?
    fetch_cache_or_call_api(:user_timeline, args[0]) {
      options = {count: 200, include_rts: true, call_count: 3}.merge(args.extract_options!)
      collect_with_max_id(:old_user_timeline, *args, options)
    }
  end

  # can't get tweets if you are not authenticated by specified user
  alias :old_mentions_timeline :mentions_timeline
  def mentions_timeline(*args)
    raise 'this method needs at least one param to use cache' if args.empty?
    raise 'this method must be called by authenticated user' unless called_by_authenticated_user?(args[0])
    fetch_cache_or_call_api(:mentions_timeline, args[0]) {
      options = {count: 200, include_rts: true, call_count: 1}.merge(args.extract_options!)
      collect_with_max_id(:old_mentions_timeline, options)
    }
  end

  def select_screen_names_replied(tweets)
    tweets.map do |t|
      $1 if t.text =~ /^(?:\.)?@(\w+)( |\W)/ # include statuses starts with .
    end.compact.uniq
  end

  # users which specified user is replying
  # in_reply_to_user_id and in_reply_to_status_id is not used because of distinguishing mentions from replies
  def replying(user)
    tweets = user_timeline(user)
    screen_names = select_screen_names_replied(tweets)
    users(screen_names)
  end

  alias :old_search :search
  def search(*args)
    raise 'this method needs at least one param to use cache' if args.empty?
    options = args.extract_options!
    options[:reduce] = false
    fetch_cache_or_call_api(:search, args[0], options) {
      options = {count: 100, result_type: :recent, call_count: 1}.merge(options)
      collect_with_max_id(:old_search, *args, options) { |response| response.attrs[:statuses] }
    }
  end

  def select_uids_replying_to(tweets)
    tweets.map do |t|
      tt = Hashie::Mash.new(t)
      tt.user.id.to_i if tt.text =~ /^(?:\.)?@(\w+)( |\W)/ # include statuses starts with .
    end.compact.uniq
  end

  # users which specified user is replied
  # when user is login you had better to call mentions_timeline
  def replied(user)
    user = self.user(user).screen_name unless user.kind_of?(String)
    if user == screen_name
      mentions_timeline(user).uniq { |m| m.user.id }.map { |m| m.user }
    else
      tweets = search('@' + user)
      uids = select_uids_replying_to(tweets)
      users(uids)
    end
  end

  def select_inactive_users(users, options = {})
    options[:authorized] = false unless options.has_key?(:authorized)
    two_weeks_ago = 2.weeks.ago.to_i
    users.select do |u|
      if options[:authorized] || !u.protected
        (Time.parse(u.status.created_at).to_i < two_weeks_ago) rescue false
      else
        false
      end
    end
  end

  def inactive_friends(user)
    select_inactive_users(friends_advanced(user))
  end

  def inactive_followers(user)
    select_inactive_users(followers_advanced(user))
  end

  def clusters_belong_to(text)
    return [] if text.blank?

    exclude_words = JSON.parse(File.read('cluster_bad_words.json'))
    special_words = JSON.parse(File.read('cluster_good_words.json'))

    # クラスタ用の単語の出現回数を記録
    cluster_word_counter =
      special_words.map { |sw| [sw, text.scan(sw)] }
        .delete_if { |item| item[1].empty? }
        .each_with_object(Hash.new(1)) { |item, memo| memo[item[0]] = item[1].size }

    # 同一文字種の繰り返しを見付ける。漢字の繰り返し、ひらがなの繰り返し、カタカナの繰り返し、など
    text.scan(/[一-龠〆ヵヶ々]+|[ぁ-んー～]+|[ァ-ヴー～]+|[ａ-ｚＡ-Ｚ０-９]+|[、。！!？?]+/).

      # 複数回繰り返される文字を除去
      map { |w| w.remove /[？！?!。、ｗ]|(ー{2,})/ }.

      # 文字数の少なすぎる単語、ひらがなだけの単語、除外単語を除去する
      delete_if { |w| w.length <= 1 || (w.length <= 2 && w =~ /^[ぁ-んー～]+$/) || exclude_words.include?(w) }.

      # 出現回数を記録
      each { |w| cluster_word_counter[w] += 1 }

    # 複数個以上見付かった単語のみを残し、出現頻度順にソート
    cluster_words = cluster_word_counter.select { |_, v| v > 3 }.sort_by { |_, v| -v }.to_h.keys

    # 出現回数上位の単語のみを返す
    cluster_words.slice(0, [cluster_words.size, 5].min)
  end

  def clusters_assigned_to

  end

  def usage_stats_wday_series_data(tweets)
    times = tweets.map { |t| t.created_at }
    wday_count = times.each_with_object((0..6).map { |n| [n, 0] }.to_h) do |time, memo|
      memo[time.wday] += 1
    end
    wday_count.map { |k, v| [I18n.t('date.abbr_day_names')[k], v] }.map do |key, value|
      {name: key, y: value, drilldown: key}
    end
  end

  def usage_stats_wday_drilldown_series(tweets)
    times = tweets.map { |t| t.created_at }
    hour_count =
      (0..6).each_with_object((0..6).map { |n| [n, nil] }.to_h) do |wday, wday_memo|
        wday_memo[wday] =
          times.select { |t| t.wday == wday }.map { |t| t.hour }.each_with_object((0..23).map { |n| [n, 0] }.to_h) do |hour, hour_memo|
            hour_memo[hour] += 1
          end
      end
    hour_count.map { |k, v| [I18n.t('date.abbr_day_names')[k], v] }.map do |key, value|
      {name: key, id: key, data: value.to_a.map{|a| [a[0].to_s, a[1]] }}
    end
  end

  def usage_stats_hour_series_data(tweets)
    times = tweets.map { |t| t.created_at }
    hour_count = times.each_with_object((0..23).map { |n| [n, 0] }.to_h) do |time, memo|
      memo[time.hour] += 1
    end
    hour_count.map do |key, value|
      {name: key.to_s, y: value, drilldown: key.to_s}
    end
  end

  def usage_stats_hour_drilldown_series(tweets)
    times = tweets.map { |t| t.created_at }
    wday_count =
      (0..23).each_with_object((0..23).map { |n| [n, nil] }.to_h) do |hour, hour_memo|
        hour_memo[hour] =
          times.select { |t| t.hour == hour }.map { |t| t.wday }.each_with_object((0..6).map { |n| [n, 0] }.to_h) do |wday, wday_memo|
            wday_memo[wday] += 1
          end
      end
    wday_count.map do |key, value|
      {name: key.to_s, id: key.to_s, data: value.to_a.map{|a| [I18n.t('date.abbr_day_names')[a[0]], a[1]] }}
    end
  end

  def usage_stats(user, options = {})
    n_days_ago = options.has_key?(:days) ? options[:days].days.ago : 365.days.ago
    tweets = options.has_key?(:tweets) ? options[:tweets] : nil
    if tweets.nil?
      tweets =
        user_timeline(user).
          map { |t| t.kind_of?(Hashie::Mash) ? t : Hashie::Mash.new(t.attrs) }.

          # TODO Use user specific time zone
          map { |t| t.created_at = ActiveSupport::TimeZone['Tokyo'].parse(t.created_at.to_s); t }.
          select { |t| t.created_at > n_days_ago }
    end
    [
      usage_stats_wday_series_data(tweets),
      usage_stats_wday_drilldown_series(tweets),
      usage_stats_hour_series_data(tweets),
      usage_stats_hour_drilldown_series(tweets)
    ]
  end

  alias :old_favorites :favorites
  def favorites(*args)
    raise 'this method needs at least one param to use cache' if args.empty?
    fetch_cache_or_call_api(:favorites, args[0]) {
      options = {count: 100, call_count: 1}.merge(args.extract_options!)
      collect_with_max_id(:old_favorites, *args, options)
    }
  end

  def favoriting(user)
    fav = favorites(user).map { |f| f.user }
    uids = fav.each_with_object(Hash.new(0)) { |user, memo| memo[user.id] += 1 }.sort_by { |_, v| -v }.to_h.keys
    uids.map { |uid| fav.find { |f| f.id.to_i == uid.to_i } }
  end

  def favorited_by(user)
  end

  def close_friends(uid, screen_name, options = {})
    options[:min] = 0 unless options.has_key?(:min)
    options[:max] = 1 unless options.has_key?(:max)
    _users = replying(uid.to_i) + replied(screen_name) + favoriting(uid.to_i)
    uids = _users.each_with_object(Hash.new(0)) { |user, memo| memo[user.id] += 1 }.
      select { |_k, v| options[:min] <= v && v <= options[:max] }.
      sort_by { |_, v| -v }.to_h.keys
    uids.map { |uid| _users.find { |u| u.id.to_i == uid.to_i } }
  end
end