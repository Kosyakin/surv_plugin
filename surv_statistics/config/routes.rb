# frozen_string_literal: true

RedmineApp::Application.routes.draw do
  scope "/projects/:project_id" do
    get 'surv_statistics', :to => 'surv_statistics#index', :as => 'project_surv_statistics'
  end
end


