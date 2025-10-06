# frozen_string_literal: true

module NewInterface
	class Hooks < Redmine::Hook::ViewListener
		# Insert scripts into the <head> for all pages
		render_on :view_layouts_base_html_head, partial: 'new_interface/assets'
	end
end

