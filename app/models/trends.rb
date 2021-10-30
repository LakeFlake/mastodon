# frozen_string_literal: true

module Trends
  def self.table_name_prefix
    'trends_'
  end

  def self.links
    @links ||= Trends::Links.new
  end

  def self.tags
    @tags ||= Trends::Tags.new
  end

  def self.register(status)
    return unless status.proper.public_visibility? && status.public_visibility? && !status.proper.account.silenced? && !status.account.silenced?

    status.proper.tags.each { |tag| tags.add(tag, status.account, status: status.proper != status ? nil : status) }
    status.proper.preview_cards.each { |preview_card| links.add(preview_card, status.account) }
  end
end
