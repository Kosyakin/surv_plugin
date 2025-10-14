# plugins/surv_time_entries_editing/init.rb
Redmine::Plugin.register :surv_time_entries_editing do
  name 'SURV Time Entries editing plugin'
  author 'Kosyakin Vladimir'
  description 'This is a plugin to modernize the time entries page in Redmine.'
  version '0.0.1'

  # Применяем патчи и хуки
  require_relative 'lib/surv_time_entries_editing/hooks'
  require_relative 'lib/surv_time_entries_editing/timelog_controller_patch'

end
