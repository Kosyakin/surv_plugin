module SurvAdminSettings
  module Policies
    module TimeEntryClosedPeriodPatch
      def self.included(base)
        base.class_eval do
          validate :sas_validate_closed_period

          private

          def sas_validate_closed_period
            date_value = (self.spent_on || self.created_on&.to_date)
            return unless date_value

            closed_date_str = Setting.plugin_surv_admin_settings['closed_period_date'] rescue nil
            return if closed_date_str.blank?

            begin
              closed_date = Date.parse(closed_date_str.to_s)
            rescue ArgumentError
              return
            end

            if date_value <= closed_date
              Rails.logger.warn "[SURV_ADMIN_SETTINGS] User #{User.current.login} (ID: #{User.current.id}) attempted to #{new_record? ? 'create' : 'modify'} time entry #{new_record? ? '(new)' : id} for date #{date_value} in closed period (closed_date: #{closed_date}) in project #{project&.identifier || 'unknown'}"
              errors.add(:base, I18n.t('surv_admin_settings.errors.closed_period'))
            end
          end
        end
      end
    end
  end
end


