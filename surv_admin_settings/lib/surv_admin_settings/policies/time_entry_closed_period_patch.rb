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
              errors.add(:base, I18n.t('surv_admin_settings.errors.closed_period'))
            end
          end
        end
      end
    end
  end
end


