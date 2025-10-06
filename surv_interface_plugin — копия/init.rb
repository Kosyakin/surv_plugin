Redmine::Plugin.register :surv_interface_plugin do
  name 'Система учета рабочего времени'
  author 'Косякин Владимир Владиславович'
  description 'Плагин реализует новые контроллеры и новые представления для корректной работы системы учета рабочего времени согласно функционально техническим требованиям'
  version '0.0.1'
end

Redmine::MenuManager.map :top_menu do |menu|
  # Изменение пунктов верхнего меню:
  # - Убираем "Домашняя страница" и "Моя страница"
  # - Добавляем "Мои трудозатраты" и "Согласование трудозатрат"
  menu.delete :home
  menu.delete :my_page

  # Добавляем пункт меню "Мои трудозатраты"
  menu.push :my_time_entries, { controller: 'my_timelog', action: 'index' },
            caption: 'Мои трудозатраты',
            after: :projects,
            if: Proc.new { User.current.logged? }

  # Добавляем пункт меню "Согласование трудозатрат"
  menu.push :time_entries_approval, { controller: 'time_approvals', action: 'index' },
            caption: 'Согласование трудозатрат',
            after: :my_time_entries,
            if: Proc.new { User.current.logged? }
end