# frozen_string_literal: true

class PreviewCardProviderFilter
  KEYS = %i(
    reviewed
    unreviewed
    pending_review
  ).freeze

  attr_reader :params

  def initialize(params)
    @params = params
  end

  def results
    scope = PreviewCardProvider.unscoped

    params.each do |key, value|
      next if key.to_s == 'page'

      scope.merge!(scope_for(key, value.to_s.strip)) if value.present?
    end

    scope.order(id: :desc)
  end

  private

  def scope_for(key, value)
    case key.to_s
    when 'reviewed'
      PreviewCardProvider.reviewed.order(reviewed_at: :desc)
    when 'unreviewed'
      PreviewCardProvider.unreviewed
    when 'pending_review'
      PreviewCardProvider.pending_review.order(requested_review_at: :desc)
    else
      raise "Unknown filter: #{key}"
    end
  end
end
