module OwnTimeEntriesVisibility
  module TimeEntriesControllerPatch
    def self.included(base)
      base.class_eval do
        alias_method :original_authorize, :authorize  # Сохраняем оригинальный метод

        def authorize(ctrl = params[:controller], action = params[:action], global = false)
          if ctrl == 'time_entries' && ['index', 'show', 'report'].include?(action) && @project.present?
            permitted = User.current.allowed_to?(:view_time_entries, @project, global: global) ||
                        User.current.allowed_to?(:view_own_time_entries, @project, global: global)
            if permitted
              return true
            else
              deny_access
              return false
            end
          else
            original_authorize(ctrl, action, global)  # Для других случаев — оригинальная проверка
          end
        end
      end
    end
  end
end