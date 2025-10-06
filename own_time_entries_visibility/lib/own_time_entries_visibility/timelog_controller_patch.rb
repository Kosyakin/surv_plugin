# plugins/own_time_entries_visibility/lib/own_time_entries_visibility/timelog_controller_patch.rb

module OwnTimeEntriesVisibility
  module TimelogControllerPatch
    def self.included(base)
      base.class_eval do
        # Используем псевдоним метода
        alias_method :original_time_entry_scope, :time_entry_scope

        # Переопределяем метод, который возвращает scope
        def time_entry_scope(options = {})
          # Получаем стандартный scope, построенный на основе фильтров @query
          scope = original_time_entry_scope(options)

          # Применяем наше условие видимости
          if should_restrict_to_own_entries?
            scope = scope.where(user_id: User.current.id)
          end

          return scope
        end

        private

        # Выносим логику проверки в отдельный метод
        def should_restrict_to_own_entries?
          # Проверяем, что мы в проекте (а не в общем списке по всем проектам)
          return false unless @project
          # Проверяем право роли, которая должна видеть только свои записи.
          User.current.allowed_to?(:view_own_time_entries, @project)
        end
      end
    end
  end
end