RedmineApp::Application.routes.draw do
  # Admin settings page for SURV plugin
  get  'surv_admin_settings/edit',   to: 'surv_admin_settings#edit',   as: 'surv_admin_settings_edit'
  post 'surv_admin_settings/update', to: 'surv_admin_settings#update', as: 'surv_admin_settings_update'
  resources :surv_admin_settings, only: [:edit, :update] do
    collection do
      post 'upload_csv'
      post 'clear_csv'
      get 'export_custom_field'
      post 'add_custom_field_value'
      post 'delete_custom_field_value'
      get 'export_group'
      post 'upload_group_preview'
      post 'update_group'
      post 'clear_group_preview'
    end
  end
end