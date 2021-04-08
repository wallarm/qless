# frozen_string_literal: true

require 'redis'

module Qless
  module RedisUnderlineClient
    # https://github.com/redis/redis-rb/compare/v3.3.5...v4.0.1#diff-06572a96a58dc510037d5efa622f9bec8519bc1beab13c9f251e97e657a9d4edR19-R20
    if ::Redis::VERSION < '4'
      def redis_underline_client(redis)
        redis.client
      end
    else
      def redis_underline_client(redis)
        redis._client
      end
    end
  end
end