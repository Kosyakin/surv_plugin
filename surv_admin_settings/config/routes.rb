RedmineApp::Application.routes.draw do
  # Admin settings page for SURV plugin
  resources :surv_admin_settings, only: [] do
    collection do
      get 'index', to: 'surv_admin_settings#index', as: 'index'
      get 'closed_period', to: 'surv_admin_settings#closed_period', as: 'closed_period'
      post 'update_closed_period', to: 'surv_admin_settings#update_closed_period', as: 'update_closed_period'
      get 'list_management', to: 'surv_admin_settings#list_management', as: 'list_management'
      get 'export_group'
      post 'upload_group_preview'
      post 'update_group'
    end
  end
end