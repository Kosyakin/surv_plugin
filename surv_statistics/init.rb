# frozen_string_literal: true

require 'redmine'

Redmine::Plugin.register :surv_statistics do
  name 'SURV Statistics'
  author 'SURV'
  version '0.0.1'
  description 'Statistics for time entries with ECharts; replaces project overview with time stats.'
  url 'https://example.invalid'

  # Replace project Overview with our new statistics page
  delete_menu_item :project_menu, :overview
  menu :project_menu,
       :overview,
       { :controller => 'surv_statistics', :action => 'index' },
       :param => :project_id,
       :caption => :label_spent_time,
       :first => true
end


