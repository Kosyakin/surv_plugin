# plugins/redmine_modern_time_entries/lib/redmine_modern_time_entries/hooks.rb
module RedmineModernTimeEntries
  class Hooks < Redmine::Hook::ViewListener
    # Этот хук вставляется в <head> каждой страницы Redmine.
    # Bcgjkmpetncz, чтобы выборочно подключить наши CSS и JS
    # только на страницах создания, редактирования и списка трудозатрат.
    def view_layouts_base_html_head(context={})
      controller = context[:controller]

      # Проверяем, что контроллер на странице трудозатрат (timelog или time_entries)
      # и что текущее действие - 'new' или 'edit'. Не ссылаемся на константы контроллеров,
      # чтобы избежать ошибок в старых версиях Redmine.
      if controller &&
         ['timelog', 'time_entries'].include?(controller.controller_name.to_s)

        # Подключаем CSS файл
        stylesheet_link_tag('modern_time_entries', :plugin => 'redmine_modern_time_entries') +
        # Подключаем JavaScript файл
        javascript_include_tag('modern_time_entries', :plugin => 'redmine_modern_time_entries')
      else
        # На других страницах ничего не добавляем
        ''
      end
    end
  end
end