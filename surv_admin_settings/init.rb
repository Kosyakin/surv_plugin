require 'redmine'

Redmine::Plugin.register :surv_admin_settings do
  name 'Admin Settings'
  author 'Косякин Владимир'
  description 'Administrative settings and policies: time visibility and role hierarchy sync'
  version '0.2.0'
  url 'Vladimir.Kosyakin@lukoil.com'
  author_url '-'

  project_module :time_tracking do
    # Оставляем существующее право, чтобы сохранить обратную совместимость
    permission :view_own_time_entries, {}, :require => :member
    # Право на согласование трудозатрат
    permission :approve_time_entries, {}, :require => :member
  end

  # Настройки плагина: дата закрытого периода
  settings default: {
    'closed_period_date' => nil
  }, partial: 'settings/surv_admin_settings'

  # Пункт меню в Администрировании
  menu :admin_menu, :surv_admin_settings, { controller: 'surv_admin_settings', action: 'edit' },
       caption: :label_surv_admin_settings_menu, html: { class: 'icon' }

  # Верхнее меню: Инструкции (вместо "Помощь")
  menu :top_menu, :instructions, '/projects/wiki/wiki',
       caption: :label_surv_instructions,
       html: { target: 'index',  class: 'help' }

  # Верхнее меню: Сообщить об ошибке\доработке (вместо "Помощь")
  menu :top_menu, :errors, '/projects/wiki/boards',
       caption: :label_surv_errors,
       html: { target: 'index',  class: 'help' }

end

# Базовые константы и утилиты
require_dependency File.expand_path('../lib/surv_admin_settings/core', __FILE__)

# Видимость трудозатрат (видит только свои записи при наличии соответствующего права)
require_dependency File.expand_path('../lib/surv_admin_settings/visibility/time_entry_patch', __FILE__)
TimeEntry.send(:include, SurvAdminSettings::Visibility::TimeEntryPatch)

require_dependency File.expand_path('../lib/surv_admin_settings/visibility/timelog_controller_patch', __FILE__)
TimelogController.send(:include, SurvAdminSettings::Visibility::TimelogControllerPatch)


# Синхронизация иерархии ролей и описание проекта
require_dependency File.expand_path('../lib/surv_admin_settings/hierarchy/member_patch', __FILE__)
Member.send(:include, SurvAdminSettings::Hierarchy::MemberPatch)

require_dependency File.expand_path('../lib/surv_admin_settings/hierarchy/member_role_patch', __FILE__)
MemberRole.send(:include, SurvAdminSettings::Hierarchy::MemberRolePatch)

# Политики/ограничения администрирования (закрытый период для трудозатрат)
require_dependency File.expand_path('../lib/surv_admin_settings/policies/time_entry_closed_period_patch', __FILE__)
TimeEntry.send(:include, SurvAdminSettings::Policies::TimeEntryClosedPeriodPatch)

# Право на согласование трудозатрат
require_dependency File.expand_path('../lib/surv_admin_settings/policies/time_entry_approval_patch', __FILE__)
TimeEntry.send(:include, SurvAdminSettings::Policies::TimeEntryApprovalPatch)

require_dependency File.expand_path('../lib/surv_admin_settings/controllers/timelog_controller_approval_patch', __FILE__)
TimelogController.send(:include, SurvAdminSettings::Controllers::TimelogControllerApprovalPatch)

# Удаление вкладки "Действия" из контроллера проектов
require_dependency File.expand_path('../lib/surv_admin_settings/controllers/projects_controller_patch', __FILE__)
ProjectsController.send(:include, SurvAdminSettings::Controllers::ProjectsControllerPatch)

