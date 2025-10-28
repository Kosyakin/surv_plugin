# plugins/redmine_modern_time_entries/config/routes.rb
RedmineApp::Application.routes.draw do
  # Коллекционный маршрут в рамках стандартного ресурса time_entries
  resources :time_entries, only: [] do
    collection do
      get 'for_date', to: 'timelog#get_time_entries_for_date', as: :for_date
    end
  end

  # Прямой маршрут через контроллер timelog (на случай, если collection-маршрут не подхватился)
  get 'timelog/for_date', to: 'timelog#get_time_entries_for_date', as: 'timelog_for_date'
end
