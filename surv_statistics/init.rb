# frozen_string_literal: true

require 'redmine'

Redmine::Plugin.register :surv_statistics do
  name 'SURV Statistics'
  author 'Vladimir Kosyakin'
  version '0.0.1'
  description 'Statistics for time entries with ECharts; replaces project overview with time stats.'
  url 'https://example.invalid'

end


# Load controller patch for timelog defaults
require_relative 'lib/surv_statistics/timelog_controller_patch'


