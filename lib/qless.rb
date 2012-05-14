require "socket"
require "redis"
require "json"
require "securerandom"

require "qless/version"
require "qless/config"
require "qless/queue"
require "qless/job"
require "qless/lua"

module Qless
  extend self

  def generate_jid
    SecureRandom.uuid.gsub('-', '')
  end

  def stringify_hash_keys(hash)
    hash.each_with_object({}) do |(key, value), result|
      result[key.to_s] = value
    end
  end

  # This is a unique identifier for the worker
  def worker_name
    @worker_name ||= [Socket.gethostname, Process.pid.to_s].join('-')
  end

  class UnsupportedRedisVersionError < StandardError; end

  class ClientJobs
    def initialize(client)
      @client = client
    end
    
    def complete(offset=0, count=25)
      @client._jobs.call([], ['complete', offset, count])
    end
    
    def tracked
      results = JSON.parse(@client._track.call([], []))
      results['jobs'] = results['jobs'].map { |j| Job.new(@client, j) }
      results
    end
    
    def tagged(tag, offset=0, count=25)
      JSON.parse(@client._tag.call([], ['get', tag, offset, count]))
    end
    
    def failed(t=nil, start=0, limit=25)
      if not t
        JSON.parse(@client._failed.call([], []))
      else
        results = JSON.parse(@client._failed.call([], [t, start, limit]))
        results['jobs'] = results['jobs'].map { |j| Job.new(@client, j) }
        results
      end
    end
    
    def [](id)
      results = @client._get.call([], [id])
      if results.nil?
        results = @client._recur.call([], ['get', id])
        if results.nil?
          return nil
        end
        return RecurringJob.new(@client, JSON.parse(results))
      end
      Job.new(@client, JSON.parse(results))
    end
  end
  
  class ClientWorkers
    def initialize(client)
      @client = client
    end
    
    def counts
      JSON.parse(@client._workers.call([], [Time.now.to_i]))
    end
    
    def [](name)
      JSON.parse(@client._workers.call([], [Time.now.to_i, name]))
    end
  end
  
  class ClientQueues
    def initialize(client)
      @client = client
    end
    
    def counts
      JSON.parse(@client._queues.call([], [Time.now.to_i]))
    end
    
    def [](name)
      Queue.new(name, @client)
    end
  end
  
  class Client
    # Lua scripts
    attr_reader :_cancel, :_complete, :_fail, :_failed, :_get, :_getconfig, :_heartbeat, :_jobs, :_peek, :_pop
    attr_reader :_priority, :_put, :_queues, :_recur, :_retry, :_setconfig, :_stats, :_tag, :_track, :_workers, :_depends
    # A real object
    attr_reader :config, :redis, :jobs, :queues, :workers
    
    def initialize(options = {})
      # This is the redis instance we're connected to
      @redis  = Redis.connect(options) # use connect so REDIS_URL will be honored
      # assert_minimum_redis_version("2.6")
      @config = Config.new(self)
      ['cancel', 'complete', 'depends', 'fail', 'failed', 'get', 'getconfig', 'heartbeat', 'jobs', 'peek', 'pop',
        'priority', 'put', 'queues', 'recur', 'retry', 'setconfig', 'stats', 'tag', 'track', 'workers'].each do |f|
        self.instance_variable_set("@_#{f}", Lua.new(f, @redis))
      end
      
      @jobs    = ClientJobs.new(self)
      @queues  = ClientQueues.new(self)
      @workers = ClientWorkers.new(self)
    end
    
    def track(jid)
      @_track.call([], ['track', jid, Time.now.to_i])
    end
    
    def untrack(jid)
      @_track.call([], ['untrack', jid, Time.now.to_i])
    end
    
    def tags(offset=0, count=100)
      JSON.parse(@_tag.call([], ['top', offset, count]))
    end
  private

    def assert_minimum_redis_version(version)
      redis_version = @redis.info.fetch("redis_version")
      return if Gem::Version.new(redis_version) >= Gem::Version.new(version)

      raise UnsupportedRedisVersionError,
        "You are running redis #{redis_version}, but qless requires at least #{version}"
    end
  end
end
