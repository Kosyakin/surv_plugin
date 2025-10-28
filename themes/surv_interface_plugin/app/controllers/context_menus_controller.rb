# frozen_string_literal: true

# Redmine - project management software
# Copyright (C) 2006-  Jean-Philippe Lang
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

class ContextMenusController < ApplicationController
  helper :watchers
  helper :issues

  before_action :find_issues, :only => :issues

  def issues
    if @issues.size == 1
      @issue = @issues.first
    end
    @issue_ids = @issues.map(&:id).sort

    @allowed_statuses = @issues.map(&:new_statuses_allowed_to).reduce(:&)

    @can = {
      :edit => @issues.all?(&:attributes_editable?),
      :log_time => @issue&.time_loggable?,
      :copy => User.current.allowed_to?(:copy_issues, @projects) && Issue.allowed_target_projects.any?,
      :add_watchers => User.current.allowed_to?(:add_issue_watchers, @projects),
      :delete => @issues.all?(&:deletable?),
      :add_subtask => @issue && !@issue.closed? && User.current.allowed_to?(:manage_subtasks, @project)
    }

    @assignables = @issues.map(&:assignable_users).reduce(:&)
    @trackers = @projects.map {|p| Issue.allowed_target_trackers(p)}.reduce(:&)
    @versions = @projects.map {|p| p.shared_versions.open}.reduce(:&)

    @priorities = IssuePriority.active.reverse
    @back = back_url
    begin
      # Recognize the controller and action from the back_url to determine
      # which view triggered the context menu.
      route = Rails.application.routes.recognize_path(@back)
      @include_delete =
        [
          {controller: 'issues', action: 'index'},
          {controller: 'gantts', action: 'show'},
          {controller: 'calendars', action: 'show'}
        ].any?(route.slice(:controller, :action))
    rescue ActionController::RoutingError
      @include_delete = false
    end

    @columns = params[:c]

    @options_by_custom_field = {}
    if @can[:edit]
      custom_fields = @issues.map(&:editable_custom_fields).reduce(:&).reject(&:multiple?).select {|field| field.format.bulk_edit_supported}
      custom_fields.each do |field|
        values = field.possible_values_options(@projects)
        if values.present?
          @options_by_custom_field[field] = values
        end
      end
    end

    @safe_attributes = @issues.map(&:safe_attribute_names).reduce(:&)
    render :layout => false
  end

  def time_entries
    # Disable context menu on /my/time_entries page
    if request.referer&.include?('/my/time_entries')
      render :plain => '', :layout => false
      return
    end

    @time_entries = TimeEntry.where(:id => params[:ids]).
      preload(:project => :time_entry_activities).
      preload(:user).to_a

    (render_404; return) unless @time_entries.present?
    if @time_entries.size == 1
      @time_entry = @time_entries.first
    end

    @projects = @time_entries.filter_map(&:project).uniq
    @project = @projects.first if @projects.size == 1
    # Hide the activity change submenu in the time entries context menu
    @activities = []

    edit_allowed = @time_entries.all? do |t|
      project = t.project
      # If user can only view own entries (has view_own_time_entries but not view_time_entries), disable editing
      can_only_view_own = User.current.allowed_to?(:view_own_time_entries, project) && !User.current.allowed_to?(:view_time_entries, project)
      t.editable_by?(User.current) && !can_only_view_own
    end
    @back = back_url

        @can = {
      # Проверка возможности ролей, если он видит в данном проекте только свои трудозатраты, то быстрые дейсвия отключены
      :edit => edit_allowed,
      :delete => User.current.allowed_to?(:delete_time_entries, @projects)
    }

    @options_by_custom_field = {}
    
    if @can[:edit]
      custom_fields = @time_entries
        .map(&:editable_custom_fields)
        .reduce(:&)
        .reject(&:multiple?)
        .select {|field| field.format.bulk_edit_supported}
        .reject {|field| field.id == 1}
      custom_fields.each do |field|
        values = field.possible_values_options(@projects)
        if values.present?
          @options_by_custom_field[field] = values
        end
      end
    end

    render :layout => false
  end

  def projects
    @projects = Project.where(id: params[:ids]).to_a
    if @projects.empty?
      render_404
      return
    end

    if @projects.size == 1
      @project = @projects.first
    end
    render layout: false
  end

  def users
    @users = User.where(id: params[:ids]).to_a

    (render_404; return) unless @users.present?
    if @users.size == 1
      @user = @users.first
    end
    render layout: false
  end
end


