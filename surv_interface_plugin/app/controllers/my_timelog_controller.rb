# frozen_string_literal: true

class MyTimelogController < ApplicationController
  menu_item :my_time_entries

  before_action :find_time_entry, :only => [:show, :edit, :update]
  before_action :check_editability, :only => [:edit, :update]
  before_action :find_time_entries, :only => [:bulk_edit, :bulk_update, :destroy]
  before_action :authorize, :only => [:show, :edit, :update, :bulk_edit, :bulk_update, :destroy]

  before_action :find_optional_issue, :only => [:new, :create]
  before_action :find_optional_project, :only => [:index, :report]

  # Allow any logged-in user to access the time entries page
  skip_before_action :authorize, only: :index
  skip_before_action :find_optional_project, only: :index
  before_action :require_login, only: :index
  before_action :find_project, only: :index
  before_action :apply_default_filters, only: :index

  accept_atom_auth :index
  accept_api_auth :index, :show, :create, :update, :destroy

  rescue_from Query::StatementInvalid, :with => :query_statement_invalid
  rescue_from Query::QueryError, :with => :query_error

  helper :issues
  include TimelogHelper
  helper :custom_fields
  include CustomFieldsHelper
  helper :queries
  include QueriesHelper

  def report
    retrieve_time_entry_query
    scope = time_entry_scope

    @report = Redmine::Helpers::TimeReport.new(@project, params[:criteria], params[:columns], scope)

    respond_to do |format|
      format.html {render :layout => !request.xhr?}
      format.csv do
        send_data(report_to_csv(@report), :type => 'text/csv; header=present',
                  :filename => 'timelog.csv')
      end
    end
  end

  def show
    respond_to do |format|
      # TODO: Implement html response
      format.html {head :not_acceptable}
      format.api
    end
  end

  def new
    @time_entry ||=
      TimeEntry.new(:project => @project, :issue => @issue,
                    :author => User.current, :spent_on => User.current.today)
    @time_entry.safe_attributes = params[:time_entry]
  end

  def create
    @time_entry ||=
      TimeEntry.new(:project => @project, :issue => @issue,
                    :author => User.current, :user => User.current,
                    :spent_on => User.current.today)
    @time_entry.safe_attributes = params[:time_entry]
    if @time_entry.project && !User.current.allowed_to?(:log_time, @time_entry.project)
      render_403
      return
    end

    call_hook(:controller_timelog_edit_before_save,
              {:params => params, :time_entry => @time_entry})

    if @time_entry.save
      respond_to do |format|
        format.html do
          flash[:notice] = l(:notice_successful_create)
          if params[:continue]
            options = {
              :time_entry => {
                :project_id => params[:time_entry][:project_id],
                :issue_id => @time_entry.issue_id,
                :spent_on => @time_entry.spent_on,
                :activity_id => @time_entry.activity_id
              },
              :back_url => params[:back_url]
            }
            if params[:project_id] && @time_entry.project
              options[:time_entry][:project_id] ||= @time_entry.project.id
              redirect_to new_project_time_entry_path(@time_entry.project, options)
            elsif params[:issue_id] && @time_entry.issue
              redirect_to new_issue_time_entry_path(@time_entry.issue, options)
            else
              redirect_to new_time_entry_path(options)
            end
          else
            redirect_back_or_default project_time_entries_path(@time_entry.project)
          end
        end
        format.api do
          render :action => 'show', :status => :created, :location => time_entry_url(@time_entry)
        end
      end
    else
      respond_to do |format|
        format.html {render :action => 'new'}
        format.api  {render_validation_errors(@time_entry)}
      end
    end
  end

  def edit
    @time_entry.safe_attributes = params[:time_entry]
  end

  def update
    @time_entry.safe_attributes = params[:time_entry]
    call_hook(:controller_timelog_edit_before_save,
              {:params => params, :time_entry => @time_entry})

    if @time_entry.save
      respond_to do |format|
        format.html do
          flash[:notice] = l(:notice_successful_update)
          redirect_back_or_default project_time_entries_path(@time_entry.project)
        end
        format.api  {render_api_ok}
      end
    else
      respond_to do |format|
        format.html {render :action => 'edit'}
        format.api  {render_validation_errors(@time_entry)}
      end
    end
  end

  def bulk_edit
    @target_projects = Project.allowed_to(:log_time).to_a
    @custom_fields = TimeEntry.first.available_custom_fields.select {|field| field.format.bulk_edit_supported}
    if params[:time_entry]
      @target_project = @target_projects.detect {|p| p.id.to_s == params[:time_entry][:project_id].to_s}
    end
    if @target_project
      @available_activities = @target_project.activities
    else
      @available_activities = @projects.map(&:activities).reduce(:&)
    end
    @time_entry_params = params[:time_entry] || {}
    @time_entry_params[:custom_field_values] ||= {}
  end

  def bulk_update
    attributes = parse_params_for_bulk_update(params[:time_entry])

    unsaved_time_entries = []
    saved_time_entries = []

    @time_entries.each do |time_entry|
      time_entry.reload
      time_entry.safe_attributes = attributes
      call_hook(
        :controller_time_entries_bulk_edit_before_save,
        {:params => params, :time_entry => time_entry}
      )
      if time_entry.save
        saved_time_entries << time_entry
      else
        unsaved_time_entries << time_entry
      end
    end

    if unsaved_time_entries.empty?
      flash[:notice] = l(:notice_successful_update) unless saved_time_entries.empty?
      redirect_back_or_default project_time_entries_path(@projects.first)
    else
      @saved_time_entries = @time_entries
      @unsaved_time_entries = unsaved_time_entries
      @time_entries = TimeEntry.where(:id => unsaved_time_entries.map(&:id)).
        preload(:project => :time_entry_activities).
        preload(:user).to_a

      bulk_edit
      render :action => 'bulk_edit'
    end
  end

  def destroy
    destroyed = TimeEntry.transaction do
      @time_entries.each do |t|
        unless t.destroy && t.destroyed?
          raise ActiveRecord::Rollback
        end
      end
    end

    respond_to do |format|
      format.html do
        if destroyed
          flash[:notice] = l(:notice_successful_delete)
        else
          flash[:error] = l(:notice_unable_delete_time_entry)
        end
        redirect_back_or_default project_time_entries_path(@projects.first), :referer => true
      end
      format.api do
        if destroyed
          render_api_ok
        else
          render_validation_errors(@time_entries)
        end
      end
    end
  end

  def index
    # Если у пользователя нет права видеть собственные трудозатраты ни в одном проекте,
    # перенаправляем: сначала на проект, где он Руководитель (роль id=4), иначе на инструкции
    begin
      unless Project.allowed_to(:view_own_time_entries).to_a.any?
        manager_role_id = (defined?(SurvAdminSettings::MANAGER_ROLE_ID) ? SurvAdminSettings::MANAGER_ROLE_ID : 4)
        membership_with_manager = User.current.memberships.includes(:roles, :project).detect do |m|
          m.roles.any? { |r| r.id.to_i == manager_role_id }
        end
        if membership_with_manager&.project
          redirect_to project_path(membership_with_manager.project)
          return
        else
          redirect_to '/projects/wiki/wiki'
          return
        end
      end
    rescue
      # В случае ошибки политики — безопасный возврат на инструкции
      redirect_to '/projects/wiki/wiki'
      return
    end

    # Находим проекты, где у пользователя есть право :view_own_time_entries
    projects_with_permission = Project.allowed_to(:view_own_time_entries).to_a
    
    # Если проект выбран, но у пользователя нет права в этом проекте - перенаправляем на проект с правом
    if @project.present?
      unless User.current.allowed_to?(:view_own_time_entries, @project)
        # Находим первый проект с правом и перенаправляем
        if projects_with_permission.any?
          target_project = projects_with_permission.first
          redirect_to my_time_entries_path(project_id: target_project.id)
          return
        end
      end
    else
      # Если проект не выбран, выбираем первый проект с правом и перенаправляем
      if projects_with_permission.any?
        target_project = projects_with_permission.first
        redirect_to my_time_entries_path(project_id: target_project.id)
        return
      end
    end

    # By default, when a project is selected, do not include subprojects
    params[:with_subprojects] = '0' if @project.present? && params[:with_subprojects].nil?
    retrieve_time_entry_query
    if @project.present?
      if @query.respond_to?(:include_subprojects=)
        @query.include_subprojects = false
      elsif @query.respond_to?(:with_subprojects=)
        @query.with_subprojects = false
      end
    end
    # Prepare user info and week range
    @current_user_name = [User.current.firstname, User.current.lastname].compact.join(' ').strip
    begin
      if params[:v] && params[:v]['spent_on'].is_a?(Array) && params[:v]['spent_on'].size >= 2
        from_str, to_str = params[:v]['spent_on'][0], params[:v]['spent_on'][1]
        @week_from = Date.parse(from_str) rescue nil
        @week_to   = Date.parse(to_str) rescue nil
      end
    rescue
      @week_from = nil
      @week_to = nil
    end
    @week_from ||= Date.today.beginning_of_week(:monday)
    @week_to   ||= (@week_from + 6)

    # Compute weekly planned hours (Mon..Thu 8.67, Fri 5.17, weekend 0)
    weekly_dates = (@week_from..@week_to).to_a
    @week_planned_hours = weekly_dates.sum do |d|
      case d.wday
      when 1,2,3,4 then 8.67
      when 5 then 5.17
      else 0.0
      end
    end
    # Remove project column when browsing across all projects
    if @project.nil? && @query.respond_to?(:has_column?) && @query.has_column?(:project)
      begin
        current_columns = @query.column_names.map { |n| n.is_a?(Symbol) ? n : n.to_s.strip.to_sym }
        @query.column_names = current_columns - [:project]
      rescue => e
        Rails.logger.warn("MyTimelogController: unable to adjust columns - #{e.class}: #{e.message}") if defined?(Rails)
      end
    end
    scope = time_entry_scope.
      preload(:issue => [:project, :tracker, :status, :assigned_to, :priority]).
      preload(:project, :user, :activity, :custom_values => :custom_field)

    respond_to do |format|
      format.html do
        @entry_count = scope.count
        @entry_pages = Paginator.new @entry_count, per_page_option, params['page']
        @entries = scope.offset(@entry_pages.offset).limit(@entry_pages.per_page).to_a

        # Build activity distribution (pie) using the full filtered scope, not just current page
        activity_buckets = {}
        scope.to_a.each do |time_entry|
          activity_id = time_entry.activity_id
          activity_name = time_entry.activity&.name || l(:label_none)
          bucket = (activity_buckets[activity_id] ||= { activity_id: activity_id, name: activity_name, value: 0.0 })
          bucket[:value] += time_entry.hours.to_f
        end
        @activity_pie_series = activity_buckets.values.map { |b| b.merge(value: b[:value].round(2)) }.
          sort_by { |item| -item[:value].to_f }

        # Weekly totals and approval breakdown based on the current filtered scope but limited to the computed week range
        week_entries = scope.where(:spent_on => @week_from..@week_to).to_a

        # Detect approval custom field by fixed id=2 (per specification)
        approved_cf = nil
        if defined?(CustomField)
          begin
            approved_cf = TimeEntryCustomField.find_by(id: 2)
          rescue
            approved_cf = nil
          end
        end

        # Helper to detect approval on an entry
        is_approved = lambda do |entry|
          return false unless approved_cf
          cv = entry.custom_values&.detect { |v| v.custom_field_id == approved_cf.id }
          return false unless cv
          val = cv.value
          # Redmine stores boolean custom field as '1' for true, '0' for false typically
          val == true || val == '1' || val.to_s.strip.downcase.in?(['true','t','yes','y','да','1'])
        end

        @week_entries = week_entries
        @week_hours_approved = 0.0
        @week_hours_unapproved = 0.0
        week_entries.each do |e|
          if is_approved.call(e)
            @week_hours_approved += e.hours.to_f
          else
            @week_hours_unapproved += e.hours.to_f
          end
        end
        @week_hours_approved = @week_hours_approved.round(2)
        @week_hours_unapproved = @week_hours_unapproved.round(2)
        @week_total_hours = (@week_hours_approved + @week_hours_unapproved).round(2)
        # Округляем до 10 минут (0.1667 часа)
        def round_to_10_minutes(hours)
          minutes = hours * 60
          rounded_minutes = (minutes / 10.0).round * 10
          (rounded_minutes / 60.0).round(2)
        end
        remaining = @week_planned_hours - @week_total_hours
        @week_remaining_hours = [round_to_10_minutes(remaining), 0.0].max
        @week_completion_percent = (@week_planned_hours > 0 ? ((@week_total_hours / @week_planned_hours) * 100.0) : 0.0).round(1)

        # User memberships with roles
        @user_memberships = User.current.memberships.includes(:project, :roles).map do |m|
          { project: m.project&.name, roles: m.roles.map(&:name) }
        end.compact

        render :layout => !request.xhr?
      end
      format.api do
        @entry_count = scope.count
        @offset, @limit = api_offset_and_limit
        @entries = scope.offset(@offset).limit(@limit).preload(:custom_values => :custom_field).to_a
      end
      format.atom do
        entries = scope.limit(Setting.feeds_limit.to_i).reorder("#{TimeEntry.table_name}.created_on DESC").to_a
        render_feed(entries, :title => l(:label_spent_time))
      end
      format.csv do
        entries = scope.to_a
        send_data(query_to_csv(entries, @query, params), :type => 'text/csv; header=present', :filename => "#{filename_for_export(@query, 'timelog')}.csv")
      end
    end
  end

  # Экран согласования трудозатрат
  def approval
    # Для авторизованных пользователей без обязательного проекта
    respond_to do |format|
      format.html { render :layout => !request.xhr? }
    end
  end

  private

  def find_time_entry
    @time_entry = TimeEntry.find(params[:id])
    @project = @time_entry.project
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def check_editability
    unless @time_entry.editable_by?(User.current)
      render_403
      return false
    end
  end

  def find_time_entries
    @time_entries = TimeEntry.where(:id => params[:id] || params[:ids]).
      preload(:project => :time_entry_activities).
      preload(:user).to_a

    raise ActiveRecord::RecordNotFound if @time_entries.empty?
    raise Unauthorized unless @time_entries.all? {|t| t.editable_by?(User.current)}

    @projects = @time_entries.filter_map(&:project).uniq
    @project = @projects.first if @projects.size == 1
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def find_optional_issue
    if params[:issue_id].present?
      @issue = Issue.find(params[:issue_id])
      @project = @issue.project
      authorize
    else
      find_optional_project
    end
  end

  def time_entry_scope(options={})
    @query.results_scope(options)
  end

  def retrieve_time_entry_query
    retrieve_query(TimeEntryQuery, false, :defaults => @default_columns_names)
  end

  def query_error(exception)
    session.delete(:time_entry_query)
    super
  end

  def find_project
    # @project variable must be set before calling the authorize filter
    @project = Project.find(params[:project_id]) if params[:project_id].present?
  end

  def apply_default_filters
    return if params[:set_filter].present? || params[:f].present?

    params[:utf8] = '✓'
    params[:set_filter] = '1'
    params[:sort] ||= 'spent_on:desc'

    # Default to current week range (Mon..Sun)
    week_start = Date.today.beginning_of_week(:monday)
    week_end = week_start + 6

    params[:f] = ['spent_on', 'author_id', '']
    params[:op] = {'spent_on' => '><', 'author_id' => '='}
    params[:v] = {
      'spent_on' => [week_start.to_s, week_end.to_s],
      'author_id' => ['me']
    }

    params[:group_by] ||= 'spent_on'
    params[:t] ||= ['hours']
  end
end


