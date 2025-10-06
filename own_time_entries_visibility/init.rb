require 'redmine'

Redmine::Plugin.register :own_time_entries_visibility do
  name 'Own Time Entries Visibility'
  author 'Косякин Владимир'
  description 'Plugin to allow viewing only own time entries for specific roles'
  version '0.1.0'
  url 'Vladimir.Kosyakin@lukoil.com'
  author_url '-'

  project_module :time_tracking do
    permission :view_own_time_entries, {}, :require => :member  # Без действий — только для чекбокса
  end
end

# Патч модели TimeEntry (остаётся без изменений)
require_dependency File.expand_path('../lib/own_time_entries_visibility/time_entry_patch', __FILE__)
TimeEntry.send(:include, OwnTimeEntriesVisibility::TimeEntryPatch)

# Патч для контроллера TimeLogController
require_dependency File.expand_path('../lib/own_time_entries_visibility/timelog_controller_patch', __FILE__)
TimelogController.send(:include, OwnTimeEntriesVisibility::TimelogControllerPatch)

# Обновление описания проекта при изменении состава участников/ролей
require_dependency File.expand_path('../lib/own_time_entries_visibility/member_patch', __FILE__)
Member.send(:include, OwnTimeEntriesVisibility::MemberPatch)

require_dependency File.expand_path('../lib/own_time_entries_visibility/member_role_patch', __FILE__)
MemberRole.send(:include, OwnTimeEntriesVisibility::MemberRolePatch)