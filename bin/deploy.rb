#!/usr/bin/env ruby

require 'optparse'

module Deploy
  module Util
    def green(str)
      puts "\e[32m#{str}\e[0m"
    end
  end

  class Server
    include Util

    attr_reader :host

    def initialize(host)
      @host = host
    end

    def current_dir
      '/var/egotter'
    end

    def execute(*cmd)
      green(cmd.join(' '))
      puts system(*cmd, exception: true)
    end

    def frontend(cmd)
      execute(cmd)
    end

    def backend(cmd)
      execute('ssh', host, "cd #{current_dir} && #{cmd}")
    end
  end

  class Web < Server
    CMD = [
        'git fetch origin',
        'git pull origin master',
        'bundle check || bundle install --path .bundle --without test development',
        'RAILS_ENV=production bundle exec rake assets:precompile',
        'sudo service puma restart',
    ]

    def before_deploy
      backend('echo "ssh connection test"')
    end

    def deploy
      before_deploy

      CMD.each do |cmd|
        backend(cmd)
      end

      after_deploy
    end

    def after_deploy
      frontend("git tag deploy-web-all-#{Time.now.to_i}")
      frontend('git push origin --tags')
    end
  end

  class Sidekiq < Server
    CMD = [
        'git fetch origin',
        'git pull origin master',
        'bundle check || bundle install --path .bundle --without test development',
        'sudo service sidekiq_misc status           && sudo service sidekiq_misc restart || :',
        'sudo service sidekiq_prompt_reports status && sudo service sidekiq_prompt_reports restart || :',
        'sudo service sidekiq status                && sudo service sidekiq restart || :',
        'sudo service sidekiq_import status         && sudo service sidekiq_import restart || :',
        'sudo service sidekiq_follow status         && sudo service sidekiq_follow force-restart || :',
        'sudo service sidekiq_unfollow status       && sudo service sidekiq_unfollow restart || :',
    ]

    def before_deploy
      backend('echo "ssh connection test"')
    end

    def deploy
      before_deploy

      CMD.each do |cmd|
        backend(cmd)
      end

      after_deploy
    end

    def after_deploy
      frontend("git tag deploy-sidekiq-all-#{Time.now.to_i}")
      frontend('git push origin --tags')
    end
  end
end

if __FILE__ == $0
  STDOUT.sync = true

  params = ARGV.getopts('r:', 'role:', 'hosts:')
  hosts = params['hosts'].split(',')

  case params['role']
  when 'web'
    hosts.each { |host| Deploy::Web.new(host).deploy }
  when 'sidekiq'
    hosts.each { |host| Deploy::Sidekiq.new(host).deploy }
  else
    puts "Invalid #{params.inspect}"
  end
end
