# frozen_string_literal: true

class PreviewCardProviderPolicy < ApplicationPolicy
  def index?
    staff?
  end
end
