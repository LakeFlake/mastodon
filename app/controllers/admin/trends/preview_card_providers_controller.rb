# frozen_string_literal: true

class Admin::Trends::PreviewCardProvidersController < Admin::BaseController
  def index
    authorize :preview_card_provider, :index?
    @preview_card_providers = filtered_preview_card_providers.page(params[:page])
  end

  private

  def filtered_preview_card_providers
    PreviewCardProviderFilter.new(filter_params).results
  end

  def filter_params
    params.slice(:page, *PreviewCardProviderFilter::KEYS).permit(:page, *PreviewCardProviderFilter::KEYS)
  end
end
