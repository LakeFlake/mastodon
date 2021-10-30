# frozen_string_literal: true

class Trends::Tags
  PREFIX               = 'trending_tags'
  THRESHOLD            = 5
  REVIEW_THRESHOLD     = 10
  MAX_SCORE_COOLDOWN   = 2.days.freeze
  MAX_SCORE_HALFLIFE   = 2.hours.freeze

  include Redisable

  def add(tag, account, status: nil, at_time: Time.now.utc)
    return unless tag.usable?

    # Even if a tag is not allowed to trend, we still need to
    # record the stats since they can be displayed in other places
    tag.history.add(account.id, at_time)
    record_use!(tag.id, at_time)

    # Only update when the tag was last used once every 12 hours
    # and only if a status is given (lets us ignore reblogs)
    tag.update(last_status_at: at_time) if status.present? && (tag.last_status_at.nil? || (tag.last_status_at < at_time && tag.last_status_at < 12.hours.ago))
  end

  def calculate(at_time = Time.now.utc)
    tag_ids = (ids_used_at(at_time) + get_ids(false, -1)).uniq
    tags    = Tag.where(id: tag_ids)

    # First pass to calculate scores and update the set

    tags.each do |tag|
      expected  = tag.history.get(at_time - 1.day).accounts.to_f
      expected  = 1.0 if expected.zero?
      observed  = tag.history.get(at_time).accounts.to_f
      max_time  = tag.max_score_at
      max_score = tag.max_score
      max_score = 0 if max_time.nil? || max_time < (at_time - MAX_SCORE_COOLDOWN)

      score = begin
        if expected > observed || observed < THRESHOLD
          0
        else
          ((observed - expected)**2) / expected
        end
      end

      if score > max_score
        max_score = score
        max_time  = at_time

        # Not interested in triggering any callbacks for this
        tag.update_columns(max_score: max_score, max_score_at: max_time)
      end

      decaying_score = max_score * (0.5**((at_time.to_f - max_time.to_f) / MAX_SCORE_HALFLIFE.to_f))

      if decaying_score.zero?
        redis.zrem("#{PREFIX}:all", tag.id)
        redis.zrem("#{PREFIX}:allowed", tag.id)
      else
        redis.zadd("#{PREFIX}:all", decaying_score, tag.id)
        redis.zadd("#{PREFIX}:allowed", decaying_score, tag.id) if tag.trendable?
      end
    end

    users_for_review = User.staff.includes(:account).to_a.select(&:allows_trending_tag_emails?)

    # Second pass to notify about previously unreviewed trends

    tags.each do |tag|
      current_rank              = redis.zrevrank("#{PREFIX}:all", tag.id)
      needs_review_notification = tag.requires_review? && !tag.requested_review?
      rank_passes_threshold     = current_rank.present? && current_rank <= REVIEW_THRESHOLD

      next unless !tag.trendable? && rank_passes_threshold && needs_review_notification

      tag.touch(:requested_review_at)

      users_for_review.each do |user|
        AdminMailer.new_trending_tag(user.account, tag).deliver_later!
      end
    end

    # Trim older items

    redis.zremrangebyscore("#{PREFIX}:all", '(0.3', '-inf')
    redis.zremrangebyscore("#{PREFIX}:allowed", '(0.3', '-inf')
  end

  def get(limit, filtered: true)
    tag_ids = get_ids(filtered, limit)
    tags = Tag.where(id: tag_ids).index_by(&:id)
    tag_ids.map { |tag_id| tags[tag_id] }.compact
  end

  def trending?(tag)
    # FIXME
    false
    # rank = redis.zrevrank(PREFIX, tag.id)
    # rank.present? && rank < LIMIT
  end

  private

  def get_ids(filtered, limit)
    redis.zrevrange(filtered ? "#{PREFIX}:allowed" : "#{PREFIX}:all", 0, limit).map(&:to_i)
  end

  def ids_used_at(at_time = Time.now.utc)
    redis.smembers("#{PREFIX}:used:#{at_time.beginning_of_day.to_i}").map(&:to_)
  end

  def record_use!(tag_id, at_time)
    key = "#{PREFIX}:used:#{at_time.beginning_of_day.to_i}"
    redis.sadd(key, tag_id)
    redis.expire(key, 1.day.seconds)
  end
end
