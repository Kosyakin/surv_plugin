module SurvAdminSettings
  module Visibility
    module TimeEntryPatch
      def self.included(base)
        base.class_eval do
          def visible?(usr = nil)
            user = usr || User.current
            if user.allowed_to?(:view_time_entries, project)
              true
            elsif user.allowed_to?(:view_own_time_entries, project) && self.user_id == user.id
              true
            else
              false
            end
          end
        end
      end
    end
  end
end


