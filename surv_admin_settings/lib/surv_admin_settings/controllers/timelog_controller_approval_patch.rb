module SurvAdminSettings
  module Controllers
    module TimelogControllerApprovalPatch
      def self.included(base)
        base.class_eval do
          alias_method :original_create, :create
          alias_method :original_update, :update

          def create
            if sas_check_approval_permission_before_action
              original_create
            else
              sas_handle_approval_permission_error
            end
          end

          def update
            if sas_check_approval_permission_before_action
              original_update
            else
              sas_handle_approval_permission_error
            end
          end

          private

          def sas_check_approval_permission_before_action
            return true unless @project
            return true unless params[:time_entry]

            # Если пользователь не автор записи и имеет право согласования
            if action_name == 'update' && @time_entry && @time_entry.user_id != User.current.id && User.current.allowed_to?(:approve_time_entries, @project)
              # Проверяем, пытается ли он изменить только поле "Согласовано"
              approval_field_value = params[:time_entry][:custom_field_values]&.dig('2')
              if approval_field_value
                current_value = approval_field_value.to_s
                original_value = @time_entry.custom_field_values.find { |cfv| cfv.custom_field_id == 2 }&.value.to_s
                if current_value != original_value
                  # Если изменилось только поле "Согласовано" - разрешаем
                  return true if sas_only_approval_field_changed?
                end
              end
              
              # Если пытается изменить другие поля - блокируем
              return false
            end

            # Проверяем изменение поля "Согласовано" для обычных пользователей
            approval_field_value = params[:time_entry][:custom_field_values]&.dig('2')
            return true unless approval_field_value

            # Для обновления проверяем, действительно ли значение изменилось
            if action_name == 'update' && @time_entry
              current_value = approval_field_value.to_s
              original_value = @time_entry.custom_field_values.find { |cfv| cfv.custom_field_id == 2 }&.value.to_s
              return true if current_value == original_value
            end

            # Проверяем права пользователя
            User.current.allowed_to?(:approve_time_entries, @project)
          end

          def sas_only_approval_field_changed?
            return false unless @time_entry && params[:time_entry]

            # Проверяем основные поля
            main_fields = %w[project_id issue_id user_id spent_on hours activity_id comments]
            main_fields.each do |field|
              if params[:time_entry][field] && params[:time_entry][field].to_s != @time_entry.send(field).to_s
                return false
              end
            end

            # Проверяем кастомные поля (кроме поля "Согласовано")
            if params[:time_entry][:custom_field_values]
              params[:time_entry][:custom_field_values].each do |field_id, value|
                next if field_id == '2' # Пропускаем поле "Согласовано"
                
                original_value = @time_entry.custom_field_values.find { |cfv| cfv.custom_field_id.to_s == field_id }&.value.to_s
                if value.to_s != original_value
                  return false
                end
              end
            end

            true
          end

          def sas_handle_approval_permission_error
            # Определяем тип ошибки на основе контекста
            if action_name == 'update' && @time_entry && @time_entry.user_id != User.current.id && User.current.allowed_to?(:approve_time_entries, @project)
              flash[:error] = I18n.t('surv_admin_settings.errors.insufficient_permissions_for_non_author')
            else
              flash[:error] = I18n.t('surv_admin_settings.errors.insufficient_permissions_for_approval_field')
            end
            
            redirect_to :back
          rescue ActionController::RedirectBackError
            redirect_to project_time_entries_path(@project)
          end
        end
      end
    end
  end
end
