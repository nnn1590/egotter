require_relative './enumerable_task'
require_relative './release_task'
require_relative './launch_task'

module Tasks
  module TaskBuilder
    module_function

    def build(params)
      case
      when params['release']
        build_release_task(params)
      when params['launch']
        build_launch_task(params)
      when params['terminate']
        build_terminate_task(params)
      when params['sync']
        build_sync_task(params)
      when params['list']
        build_list_task(params)
      else
        raise "Invalid action params=#{params.inspect}"
      end
    end

    def build_release_task(params)
      role = params['role']
      hosts = params['hosts'].split(',')

      if role == 'web'
        if hosts.size > 1
          Tasks::EnumerableTask.new(hosts.map { |host| Tasks::ReleaseWebTask.new(host) })
        else
          Tasks::ReleaseWebTask.new(hosts[0])
        end
      elsif role == 'sidekiq'
        if hosts.size > 1
          Tasks::EnumerableTask.new(hosts.map { |host| Tasks::ReleaseSidekiqTask.new(host) })
        else
          Tasks::ReleaseSidekiqTask.new(hosts[0])
        end
      else
        raise "Invalid role params=#{params.inspect}"
      end
    end

    def build_launch_task(params)
      if multiple_task?(params)
        count = params['count'].to_i
        tasks = count.times.map { Tasks::LaunchTask.build(params) }

        DeployRuby.logger.info "Launch instances in parallel params=#{params.inspect}"
        tasks.map.with_index do |task, i|
          Thread.new { task.launch_instance(i) }
        end.each(&:join)

        Tasks::EnumerableTask.new(tasks)
      else
        Tasks::LaunchTask.build(params)
      end
    end

    def build_terminate_task(params)
      if multiple_task?(params)
        Tasks::EnumerableTask.new(params['count'].to_i.times.map { Taskbooks::TerminateTask.build(params) })
      else
        Taskbooks::TerminateTask.build(params)
      end
    end

    def build_sync_task(params)
      Taskbooks::SyncTask.build(params)
    end

    def build_list_task(params)
      Taskbooks::ListTask.build(params)
    end

    def multiple_task?(params)
      params['count'] && params['count'].to_i > 1
    end
  end
end