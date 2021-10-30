# frozen_string_literal: true

class Trends::Links
  PREFIX           = 'trending_links'
  THRESHOLD        = 5
  REVIEW_THRESHOLD = 10

  include Redisable

  def add(link, account)
    return unless link.appropriate_for_trends?

    link.history.add(account.id)
    record_use!(link.id)
  end

  def get(limit, filtered: true)
    link_ids = get_ids(filtered, limit)
    preview_cards = PreviewCard.where(id: link_ids).index_by(&:id)
    link_ids.map { |link_id| preview_cards[link_id] }.compact
  end

  def calculate(at_time = Time.now.utc)
    link_ids = (ids_used_at(at_time) + get_ids(false, -1)).uniq
    links    = PreviewCard.where(id: link_ids)

    # First pass to calculate scores and update the set

    links.each do |link|
      expected  = link.history.get(at_time - 1.day).accounts.to_f
      expected  = 1.0 if expected.zero?
      observed  = link.history.get(at_time).accounts.to_f

      score = begin
        if expected > observed || observed < THRESHOLD
          0
        else
          ((observed - expected)**2) / expected
        end
      end

      if score.zero?
        redis.zrem("#{PREFIX}:all", link.id)
        redis.zrem("#{PREFIX}:allowed", link.id)
      else
        redis.zadd("#{PREFIX}:all", score, link.id)
        redis.zadd("#{PREFIX}:allowed", score, link.id) if link.provider&.trendable?
      end
    end

    users_for_review = User.staff.includes(:account).to_a.select(&:allows_trending_tag_emails?)

    # Second pass to notify about previously unreviewed trends

    links.each do |link|
      provider                  = link.provider
      current_rank              = redis.zrevrank("#{PREFIX}:all", link.id)
      needs_review_notification = provider.requires_review? && !provider.review_requested?
      rank_passes_threshold     = current_rank.present? && current_rank <= REVIEW_THRESHOLD

      next unless !provider.trendable? && rank_passes_threshold && needs_review_notification

      provider.touch(:reviewed_requested_at)

      users_for_review.each do |user|
        AdminMailer.new_trending_link(user.account, link).deliver_later!
      end
    end

    # Trim older items

    redis.zremrangebyscore("#{PREFIX}:all", '(0.3', '-inf')
    redis.zremrangebyscore("#{PREFIX}:allowed", '(0.3', '-inf')
  end

  private

  def get_ids(filtered, limit)
    redis.zrevrange(filtered ? "#{PREFIX}:allowed" : "#{PREFIX}:all", 0, limit).map(&:to_i)
  end

  def ids_used_at(at_time = Time.now.utc)
    redis.smembers("#{PREFIX}:used:#{at_time.beginning_of_day.to_i}").map(&:to_i)
  end

  def record_use!(link_id, at_time = Time.now.utc)
    key = "#{PREFIX}:used:#{at_time.beginning_of_day.to_i}"

    redis.sadd(key, link_id)
    redis.expire(key, 1.day.seconds)
  end
end
