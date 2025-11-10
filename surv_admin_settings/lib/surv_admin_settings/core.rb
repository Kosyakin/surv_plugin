module SurvAdminSettings
  # Zeitwerk ожидает эту константу для файла core.rb
  module Core
  end

  # Ролевые константы (id соответствуют ТЗ)
  EMPLOYEE_ROLE_ID = 3
  MANAGER_ROLE_ID = 4
  CHILD_LEADERSHIP_ROLE_ID = 5

  # Генерирует строку описания проекта на основе участников с ролью Руководитель
  def self.generate_project_members_description(project)
    members = project.members.includes(:user, :roles).to_a
    manager_names = members.filter_map do |member|
      next unless member.user
      has_manager_role = member.roles.any? { |role| role.id.to_i == MANAGER_ROLE_ID }
      has_manager_role ? member.user.name : nil
    end
    manager_names.uniq.sort.join(', ')
  end

  # Гарантирует синхронизацию ролей для участника с ролью Руководитель:
  # - роль Сотрудник в родительском проекте
  # - роль Руководство во всех дочерних проектах (включая вложенные)
  def self.ensure_hierarchy_roles_for_manager(member)
    return unless member && member.project
    is_manager = member.roles.any? { |r| r.id.to_i == MANAGER_ROLE_ID }
    return unless is_manager

    ensure_parent_employee_for_manager(member)
    ensure_descendant_leadership_for_manager(member)
  end

  def self.ensure_parent_employee_for_manager(member)
    parent_project = member.project.parent
    # Пропускаем, если родительский проект является корнем (нет своего родителя)
    return unless parent_project && parent_project.parent
    employee_role = Role.find_by_id(EMPLOYEE_ROLE_ID)
    return unless employee_role

    parent_membership = Member.find_or_initialize_by(project_id: parent_project.id, user_id: member.user_id)
    changed = false
    if parent_membership.new_record?
      parent_membership.roles = [employee_role]
      parent_membership.save(validate: false)
      changed = true
    elsif !parent_membership.roles.exists?(employee_role.id)
      parent_membership.roles << employee_role
      changed = true
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
      elsif !child_membership.roles.exists?(leadership_role.id)
        child_membership.roles << leadership_role
        changed = true
      end

      if changed
        description_text = generate_project_members_description(child_project)
        child_project.update_column(:description, description_text)
      end
    end
  end
end


