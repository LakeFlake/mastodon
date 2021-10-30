# frozen_string_literal: true

class Trends::History
  class Day
    include Redisable

    EXPIRE_AFTER = 7.days.seconds

    def initialize(prefix, id, day)
      @prefix = prefix
      @id     = id
      @day    = day.beginning_of_day
    end

    attr_reader :day

    def accounts
      redis.pfcount(key_for(:accounts))
    end

    def uses
      redis.get(key_for(:uses))&.to_i || 0
    end

    def add(account_id)
      redis.pipelined do
        redis.incrby(key_for(:uses), 1)
        redis.pfadd(key_for(:accounts), account_id)
        redis.expire(key_for(:uses), EXPIRE_AFTER)
        redis.expire(key_for(:accounts), EXPIRE_AFTER)
      end
    end

    def as_json
      { day: day.to_i.to_s, accounts: accounts.to_s, uses: uses.to_s }
    end

    private

    def key_for(suffix)
      "activity:#{@prefix}:#{@id}:#{day.to_i}:#{suffix}"
    end
  end

  def initialize(prefix, id)
    @prefix = prefix
    @id     = id
  end

  def get(date)
    Day.new(@prefix, @id, date)
  end

  def add(account_id, at_time = Time.now.utc)
    Day.new(@prefix, @id, at_time).add(account_id)
  end

  def as_json
    (0...7).map { |i| get(i.days.ago).as_json }
  end
end
