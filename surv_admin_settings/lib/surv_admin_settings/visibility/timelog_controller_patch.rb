module SurvAdminSettings
  module Visibility
    module TimelogControllerPatch
      def self.included(base)
        base.class_eval do
          alias_method :original_time_entry_scope, :time_entry_scope

          def time_entry_scope(options = {})
            scope = original_time_entry_scope(options)
            if should_restrict_to_own_entries?
              scope = scope.where(user_id: User.current.id)
            end
            scope
          end

          private

          def should_restrict_to_own_entries?
            return false unless @project
            User.current.allowed_to?(:view_own_time_entries, @project)
          end
        end
      end
    end
  end
end


