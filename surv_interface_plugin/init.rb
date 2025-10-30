Redmine::Plugin.register :surv_interface_plugin do
  name 'Система учета рабочего времени'
  author 'Косякин Владимир Владиславович'
  description 'Плагин реализует новые контроллеры и новые представления для корректной работы системы учета рабочего времени согласно функционально техническим требованиям'
  version '0.1'

  # Добавляем права доступа для существующих контроллеров
  permission :my_time_entries, { :my_timelog => [:index] }, :public => true
  permission :time_entries_approval, { :time_approvals => [:index] }, :public => true
  
  # Добавляем пункты меню для существующих контроллеров в меню проекта
  menu :project_menu, :my_time_entries, { :controller => 'my_timelog', :action => 'index' }, 
        :caption => 'Мои трудозатраты', 
        :after => :activity
        
  menu :project_menu, :time_entries_approval, { :controller => 'time_approvals', :action => 'index' }, 
        :caption => 'Согласование трудозатрат', 
        :after => :my_time_entries

  # Добавляем пункты в главное меню приложения (когда проект не выбран)
  menu :application_menu, :my_time_entries, { :controller => 'my_timelog', :action => 'index' }, 
        :caption => 'Мои трудозатраты'

  menu :application_menu, :time_entries_approval, { :controller => 'time_approvals', :action => 'index' }, 
        :caption => 'Согласование трудозатрат', 
        :after => :my_time_entries
end

Redmine::MenuManager.map :top_menu do |menu|
  # Изменение пунктов верхнего меню:
  # - Убираем "Домашняя страница" и "Моя страница"
  # - Добавляем "Мои трудозатраты" и "Согласование трудозатрат"
  menu.delete :home
  menu.delete :my_page
  # Заменяем стандартный пункт "Помощь" на ссылку на внутренние инструкции
  menu.delete :help
end

Redmine::MenuManager.map :project_menu do |menu|
  menu.delete :activity # Убираем пункт меню activity из меню проекта
end

Redmine::MenuManager.map :application_menu do |menu|
  menu.delete :activity # Убираем пункт меню activity из меню приложения
  menu.delete :time_entries # Убираем пункт меню time_entries из меню приложения

end