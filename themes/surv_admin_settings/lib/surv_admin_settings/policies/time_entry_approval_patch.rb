module SurvAdminSettings
  module Policies
    module TimeEntryApprovalPatch
      def self.included(base)
        base.class_eval do
          validate :sas_validate_approval_field_permission, :on => [:create, :update]

          private

          def sas_validate_approval_field_permission
            return unless project
            return unless custom_field_values_changed?

            # Проверяем изменение поля "Согласовано" (custom_field id="2")
            approval_field = custom_field_values.find { |cfv| cfv.custom_field_id == 2 }
            
            # Если пользователь - автор записи
            if user_id == User.current.id
              # Автор НЕ может изменять поле "Согласовано" в своих записях при обновлении
              if approval_field && !new_record?
                current_value = approval_field.value.to_s
                original_value = approval_field.value_was.to_s
                if current_value != original_value
                  Rails.logger.warn "[SURV_ADMIN_SETTINGS] User #{User.current.login} (ID: #{User.current.id}) attempted to modify approval field in own time entry #{id} in project #{project.identifier}"
                  errors.add(:base, I18n.t('surv_admin_settings.errors.author_cannot_approve_own_entries'))
                  return
                end
              end
              return # Автор может изменять все остальные поля в своих записях
            end
            
            # Если пользователь не автор записи и имеет право согласования
            if !new_record? && User.current.allowed_to?(:approve_time_entries, project)
              # Если он пытается изменить поле "Согласовано" - разрешаем
              if approval_field
                current_value = approval_field.value.to_s
                original_value = approval_field.value_was.to_s
                if current_value != original_value
                  Rails.logger.info "[SURV_ADMIN_SETTINGS] User #{User.current.login} (ID: #{User.current.id}) approved time entry #{id} in project #{project.identifier}"
                  return # Разрешаем изменение поля "Согласовано"
                end
              end
              
              # Если он пытается изменить другие поля - блокируем
              Rails.logger.warn "[SURV_ADMIN_SETTINGS] User #{User.current.login} (ID: #{User.current.id}) attempted to modify non-approval fields in time entry #{id} (author: #{user_id}) in project #{project.identifier}"
              errors.add(:base, I18n.t('surv_admin_settings.errors.insufficient_permissions_for_non_author'))
              return
            end

            # Если пользователь пытается изменить поле "Согласовано" без права
            if approval_field
              current_value = approval_field.value.to_s
              original_value = approval_field.value_was.to_s
              if current_value != original_value
                unless User.current.allowed_to?(:approve_time_entries, project)
                  Rails.logger.warn "[SURV_ADMIN_SETTINGS] User #{User.current.login} (ID: #{User.current.id}) attempted to modify approval field without permission in time entry #{id} in project #{project.identifier}"
                  errors.add(:base, I18n.t('surv_admin_settings.errors.insufficient_permissions_for_approval_field'))
                end
              end
            end
          end
        end
      end
    end
  end
end
