# frozen_string_literal: true

require_relative 'lib/new_interface'

Redmine::Plugin.register :new_interface do
	name 'New Interface Plugin'
	author 'Auto'
	description 'Hides Overview and Activity; redirects project to Spent time'
	version '0.1.0'
	url 'https://example.invalid/new_interface'
	author_url 'https://example.invalid'
end

