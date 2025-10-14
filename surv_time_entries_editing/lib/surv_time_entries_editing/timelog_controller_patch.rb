# plugins/surv_time_entries_editing/lib/surv_time_entries_editing/timelog_controller_patch.rb
require_dependency 'timelog_controller'

module SurvTimeEntriesEditing
  module TimelogControllerPatch
    def self.included(base)
      base.extend(ClassMethods)
      base.class_eval do
        unloadable

        # Возвращает трудозатраты за дату с возможной фильтрацией по пользователю/проекту
        def get_time_entries_for_date
          date_str = params[:date]
          user_id_param = params[:user_id]
          project_id_param = params[:project_id]

          # Обработка пустых строк из форм
          user_id = (user_id_param.respond_to?(:present?) && user_id_param.present?) ? user_id_param : User.current.id
          project_id = (project_id_param.respond_to?(:present?) && project_id_param.present?) ? project_id_param : nil

          begin
            date = Date.parse(date_str) if date_str.present?
          rescue ArgumentError
            render json: { error: 'Неверный формат даты' }, status: 400
            return
          end
          unless date
            render json: { error: 'Дата не указана' }, status: 400
            return
          end

          user = User.find_by(id: user_id)
          unless user
            render json: { error: 'Пользователь не найден' }, status: 404
            return
          end

          # Проверка прав:
          # - Сам пользователь всегда может видеть свои записи
          # - Администратор всегда может видеть
          # - Если указан проект, проверяем право log_time_for_other_users в проекте
          # - Если проект не указан, допускаем глобальное право
          allowed = (User.current.id == user.id) || User.current.admin?
          project = nil
          if project_id
            begin
              project = Project.find(project_id)
            rescue ActiveRecord::RecordNotFound
              render json: { error: 'Проект не найден' }, status: 404
              return
            end
            allowed ||= User.current.allowed_to?(:log_time_for_other_users, project)
          else
            allowed ||= User.current.allowed_to?(:log_time_for_other_users, nil, :global => true)
          end
          unless allowed
            render json: { error: 'Нет прав для просмотра трудозатрат этого пользователя' }, status: 403
            return
          end

          scope = TimeEntry.where(user_id: user.id, spent_on: date)
          scope = scope.where(project_id: project_id) if project_id
          time_entries = scope.includes(:project, :activity, :issue).order(:created_on)

          total_hours = time_entries.sum(:hours)
          entries_data = time_entries.map do |entry|
            {
              id: entry.id,
              hours: entry.hours,
              comments: entry.comments || '',
              activity_name: entry.activity&.name || '',
              activity_id: entry.activity_id,
              project_name: entry.project&.name || '',
              project_id: entry.project_id,
              issue_subject: entry.issue&.subject || '',
              issue_id: entry.issue_id,
              created_on: (entry.created_on ? entry.created_on.strftime('%H:%M') : '')
            }
          end

          render json: {
            date: date.strftime('%d.%m.%Y'),
            total_hours: total_hours,
            entries_count: entries_data.length,
            entries: entries_data
          }
        end

        private
      end
    end

    module ClassMethods
    end
  end
end

# Применяем патч
TimelogController.send(:include, SurvTimeEntriesEditing::TimelogControllerPatch)