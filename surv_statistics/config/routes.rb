# frozen_string_literal: true

RedmineApp::Application.routes.draw do
  scope "/projects/:project_id" do
    get 'surv_statistics', :to => 'surv_statistics#index', :as => 'project_surv_statistics'
  end

  # Redirect /projects/wiki to /projects/wiki/wiki for wiki projects
  get '/projects/wiki', :to => redirect('/projects/wiki/wiki'), :constraints => lambda { |request|
    # Check if project with identifier 'wiki' exists
    project = Project.find_by(identifier: 'wiki')
    project.present?
  }
end


