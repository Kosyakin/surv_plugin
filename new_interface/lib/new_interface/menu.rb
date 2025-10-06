# frozen_string_literal: true

module NewInterface
	module Menu
		def self.apply
			# Remove 'overview' and 'activity' from project menu for all projects
			[:overview, :activity].each do |item|
				if Redmine::MenuManager.map(:project_menu).exists?(item)
					Redmine::MenuManager.map(:project_menu).delete(item)
				end
			end
		end
	end
end

# Apply immediately on load
NewInterface::Menu.apply
