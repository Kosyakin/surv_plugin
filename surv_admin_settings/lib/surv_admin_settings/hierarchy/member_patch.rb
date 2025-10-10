module SurvAdminSettings
  module Hierarchy
    module MemberPatch
      def self.included(base)
        base.class_eval do
          after_commit :sas_update_project_description_on_change
          after_destroy :sas_update_project_description_on_destroy

          private

          def sas_update_project_description_on_change
            sas_refresh_project_description
          end

          def sas_update_project_description_on_destroy
            sas_refresh_project_description
          end

          def sas_refresh_project_description
            return unless project
            description_text = SurvAdminSettings.generate_project_members_description(project)
            project.update_column(:description, description_text)
            SurvAdminSettings.ensure_hierarchy_roles_for_manager(self)
          end
        end
      end
    end
  end
end


