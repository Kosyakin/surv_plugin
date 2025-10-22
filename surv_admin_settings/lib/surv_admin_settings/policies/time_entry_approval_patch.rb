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
            
            # Если пользователь не автор записи и имеет право согласования
            if !new_record? && user_id != User.current.id && User.current.allowed_to?(:approve_time_entries, project)
              # Если он пытается изменить поле "Согласовано" - разрешаем
              if approval_field
                current_value = approval_field.value.to_s
                original_value = approval_field.value_was.to_s
                if current_value != original_value
                  return # Разрешаем изменение поля "Согласовано"
                end
              end
              
              # Если он пытается изменить другие поля - блокируем
              errors.add(:base, I18n.t('surv_admin_settings.errors.insufficient_permissions_for_non_author'))
              return
            end

            # Если пользователь пытается изменить поле "Согласовано" без права
            if approval_field
              current_value = approval_field.value.to_s
              original_value = approval_field.value_was.to_s
              if current_value != original_value
                unless User.current.allowed_to?(:approve_time_entries, project)
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
