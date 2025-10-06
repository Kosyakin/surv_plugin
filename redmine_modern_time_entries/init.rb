# plugins/redmine_modern_time_entries/init.rb
Redmine::Plugin.register :redmine_modern_time_entries do
  name 'Redmine Modern Time Entries plugin'
  author 'Kosyakin Vladimir'
  description 'This is a plugin to modernize the time entries page in Redmine.'
  version '0.0.1'

  # Применяем патчи и хуки
  require_relative 'lib/redmine_modern_time_entries/hooks'

 end