# plugins/surv_time_entries_editing/lib/surv_time_entries_editing/hooks.rb
module SurvTimeEntriesEditing
  class Hooks < Redmine::Hook::ViewListener
    # Этот хук вставляется в <head> каждой страницы Redmine.
    # Bcgjkmpetncz, чтобы выборочно подключить наши CSS и JS
    # только на страницах создания, редактирования и списка трудозатрат.
    def view_layouts_base_html_head(context={})
      controller = context[:controller]

      # Проверяем, что контроллер на странице трудозатрат (timelog или time_entries)
      # и что текущее действие - 'new' или 'edit'. Не ссылаемся на константы контроллеров,
      # чтобы избежать ошибок в старых версиях Redmine.
      if controller && ['timelog', 'time_entries'].include?(controller.controller_name.to_s)
        # Подключаем CSS и JS из текущего плагина
        stylesheet_link_tag('modern_time_entries', :plugin => 'surv_time_entries_editing') +
        javascript_include_tag('modern_time_entries', :plugin => 'surv_time_entries_editing')
      else
        # На других страницах ничего не добавляем
        ''
      end
    end
  end
end
