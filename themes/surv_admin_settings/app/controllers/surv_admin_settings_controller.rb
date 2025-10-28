class SurvAdminSettingsController < ApplicationController
  layout 'admin'
  self.main_menu = false

  before_action :require_admin

  def edit
    @closed_period_date = Setting.plugin_surv_admin_settings['closed_period_date']
  end

  def update
    closed_date = params.dig(:settings, :closed_period_date)
    Setting.plugin_surv_admin_settings = { 'closed_period_date' => closed_date }
    flash[:notice] = l(:notice_successful_update)
    redirect_to action: :edit
  end
end


