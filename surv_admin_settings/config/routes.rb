RedmineApp::Application.routes.draw do
  # Admin settings page for SURV plugin
  get  'surv_admin_settings/edit',   to: 'surv_admin_settings#edit',   as: 'surv_admin_settings_edit'
  post 'surv_admin_settings/update', to: 'surv_admin_settings#update', as: 'surv_admin_settings_update'
end





