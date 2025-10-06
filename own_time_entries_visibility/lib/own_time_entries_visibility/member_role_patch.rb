module OwnTimeEntriesVisibility
  module MemberRolePatch
    def self.included(base)
      base.class_eval do
        after_commit :otv_update_project_description
        after_commit :otv_ensure_parent_membership_for_manager, on: :create
        after_commit :otv_ensure_child_leadership_roles_for_parent_manager, on: :create
        after_commit :otv_sync_hierarchy_for_member_change
        after_destroy :otv_update_project_description

        private

        def otv_update_project_description
          return unless member && member.project
          project = member.project
          description_text = OwnTimeEntriesVisibility.generate_project_members_description(project)
          project.update_column(:description, description_text)
        end
        # Универсальная синхронизация вверх/вниз после любых изменений ролей участника
        def otv_sync_hierarchy_for_member_change
          return unless member && member.project
          OwnTimeEntriesVisibility.ensure_hierarchy_roles_for_manager(member)
        end

        # Если пользователю назначена роль "Руководитель" в проекте, то добавить его
        # в родительский проект с ролью "Сотрудник".
        def otv_ensure_parent_membership_for_manager
          return unless member && member.project
          return unless role_id.to_i == OwnTimeEntriesVisibility::MANAGER_ROLE_ID

          parent_project = member.project.parent
          return unless parent_project

          employee_role = Role.find_by_id(OwnTimeEntriesVisibility::EMPLOYEE_ROLE_ID)
          return unless employee_role

          parent_membership = Member.find_or_initialize_by(project_id: parent_project.id, user_id: member.user_id)
          parent_changed = false

          if parent_membership.new_record?
            parent_membership.roles = [employee_role]
            parent_membership.save(validate: false)
            parent_changed = true
          else
            unless parent_membership.roles.exists?(employee_role.id)
              parent_membership.roles << employee_role
              parent_changed = true
            end
          end

          if parent_changed
            description_text = OwnTimeEntriesVisibility.generate_project_members_description(parent_project)
            parent_project.update_column(:description, description_text)
          end
        end

        # Если в проекте пользователю назначена роль "Руководитель",
        # выдать ему роль "Руководство" во всех дочерних проектах.
        def otv_ensure_child_leadership_roles_for_parent_manager
          return unless member && member.project
          return unless role_id.to_i == OwnTimeEntriesVisibility::MANAGER_ROLE_ID

          leadership_role = Role.find_by_id(OwnTimeEntriesVisibility::CHILD_LEADERSHIP_ROLE_ID)
          return unless leadership_role

          # Проходим по всем потомкам (не только прямым детям)
          member.project.descendants.each do |child_project|
            child_membership = Member.find_or_initialize_by(project_id: child_project.id, user_id: member.user_id)
            changed = false
            if child_membership.new_record?
              child_membership.roles = [leadership_role]
              child_membership.save(validate: false)
              changed = true
            else
              unless child_membership.roles.exists?(leadership_role.id)
                child_membership.roles << leadership_role
                changed = true
              end
            end

            if changed
              description_text = OwnTimeEntriesVisibility.generate_project_members_description(child_project)
              child_project.update_column(:description, description_text)
            end
          end
        end
      end
    end
  end
end


