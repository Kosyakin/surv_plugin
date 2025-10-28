RedmineApp::Application.routes.draw do
  get 'my/time_entries', :to => 'my_timelog#index', :as => 'my_time_entries'
  get 'approvals/time_entries', :to => 'time_approvals#index', :as => 'time_entries_approval'
  
  # If you want to replace the homepage without touching core routes, uncomment:
  # root :to => 'my_timelog#index'
end
