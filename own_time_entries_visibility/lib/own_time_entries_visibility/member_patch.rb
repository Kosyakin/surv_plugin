module OwnTimeEntriesVisibility
  module MemberPatch
    def self.included(base)
      base.class_eval do
        after_commit :otv_update_project_description_on_change
        after_destroy :otv_update_project_description_on_destroy

        private

        def otv_update_project_description_on_change
          otv_refresh_project_description
        end

        def otv_update_project_description_on_destroy
          otv_refresh_project_description
        end

        def otv_refresh_project_description
          return unless project
          description_text = OwnTimeEntriesVisibility.generate_project_members_description(project)
          # Обновляем без валидаций/коллбеков проекта, чтобы избежать рекурсий
          project.update_column(:description, description_text)
          # Дополнительно синхронизируем роли вверх/вниз, если членство содержит роль Руководитель
          OwnTimeEntriesVisibility.ensure_hierarchy_roles_for_manager(self)
        end
      end
    end
  end

  # Генерация полного описания проекта на основе участников и их ролей
  def self.generate_project_members_description(project)
    members = project.members.includes(:user, :roles).to_a
    manager_names = []

    members.each do |member|
      next unless member.user
      has_manager = member.roles.any? { |role| role.id.to_i == OwnTimeEntriesVisibility::MANAGER_ROLE_ID }
      next unless has_manager
      manager_names << member.user.name
    end

    manager_names.uniq.sort.join(', ')
  end

  # Константы ролей (по id согласно ТЗ)
  EMPLOYEE_ROLE_ID = 3
  MANAGER_ROLE_ID = 4
  CHILD_LEADERSHIP_ROLE_ID = 5

  # Проверяет, что у члена проекта есть роль Руководитель, и обеспечивает:
  # - наличие роли Подчиненный в родительском проекте
  # - наличие роли Руководство во всех дочерних проектах (включая вложенные)
  def self.ensure_hierarchy_roles_for_manager(member)
    return unless member && member.project
    manager_role_present = member.roles.any? { |r| r.id.to_i == MANAGER_ROLE_ID }
    return unless manager_role_present

    ensure_parent_employee_for_manager(member)
    ensure_descendant_leadership_for_manager(member)
  end

  def self.ensure_parent_employee_for_manager(member)
    parent_project = member.project.parent
    return unless parent_project
    employee_role = Role.find_by_id(EMPLOYEE_ROLE_ID)
    return unless employee_role

    parent_membership = Member.find_or_initialize_by(project_id: parent_project.id, user_id: member.user_id)
    changed = false
    if parent_membership.new_record?
      parent_membership.roles = [employee_role]
      parent_membership.save(validate: false)
      changed = true
    else
      unless parent_membership.roles.exists?(employee_role.id)
        parent_membership.roles << employee_role
        changed = true
      end
    end
    if changed
      description_text = generate_project_members_description(parent_project)
      parent_project.update_column(:description, description_text)
    end
  end

  def self.ensure_descendant_leadership_for_manager(member)
    leadership_role = Role.find_by_id(CHILD_LEADERSHIP_ROLE_ID)
    return unless leadership_role
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
        description_text = generate_project_members_description(child_project)
        child_project.update_column(:description, description_text)
      end
    end
  end
end


