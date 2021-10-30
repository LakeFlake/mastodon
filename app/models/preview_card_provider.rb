# frozen_string_literal: true
# == Schema Information
#
# Table name: preview_card_providers
#
#  id                  :bigint(8)        not null, primary key
#  domain              :string           default(""), not null
#  icon_file_name      :string
#  icon_content_type   :string
#  icon_file_size      :bigint(8)
#  icon_updated_at     :datetime
#  trendable           :boolean
#  reviewed_at         :datetime
#  review_requested_at :datetime
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#

class PreviewCardProvider < ApplicationRecord
  include DomainNormalizable
  include Attachmentable

  ICON_MIME_TYPES = %w(image/x-icon image/vnd.microsoft.icon image/png).freeze
  LIMIT = 1.megabyte

  validates :domain, presence: true, uniqueness: true, domain: true

  has_attached_file :icon, styles: { static: { format: 'png', convert_options: '-coalesce -strip' } }, validate_media_type: false
  validates_attachment :icon, content_type: { content_type: ICON_MIME_TYPES }, size: { less_than: LIMIT }
  remotable_attachment :icon, LIMIT

  scope :reviewed, -> { where.not(reviewed_at: nil) }
  scope :unreviewed, -> { where(reviewed_at: nil) }
  scope :pending_review, -> { unreviewed.where.not(requested_review_at: nil) }

  def requires_review?
    reviewed_at.nil?
  end

  def reviewed?
    reviewed_at.present?
  end

  def requested_review?
    requested_review_at.present?
  end

  def self.matching_domain(domain)
    segments = domain.split('.')
    where(domain: segments.map.with_index { |_, i| segments[i..-1].join('.') }).order(Arel.sql('char_length(domain) desc')).first
  end
end
