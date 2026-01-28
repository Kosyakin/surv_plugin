# frozen_string_literal: true

class TimeApprovalsController < ApplicationController
  menu_item :time_entries_approval

  before_action :find_time_entry, :only => [:show, :edit, :update]
  before_action :check_editability, :only => [:edit, :update]
  before_action :find_time_entries, :only => [:bulk_edit, :bulk_update, :destroy]
  before_action :authorize, :only => [:show, :edit, :update, :bulk_edit, :bulk_update, :destroy]

  before_action :find_optional_issue, :only => [:new, :create]
  before_action :find_optional_project, :only => [:index, :report]

  # Разрешаем доступ всем авторизованным пользователям, проект не обязателен
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
    # If no project selected, default to a project where the user has role id=4
    if @project.nil?
      membership_with_role4 = User.current.memberships.includes(:roles, :project).detect do |m|
        m.roles.any? { |r| r.id.to_i == 4 }
      end
      if membership_with_role4&.project
        @project = membership_with_role4.project
        params[:project_id] = @project.id
      else
        # Если не найден проект с правами на согласование, возвращаем обратно с уведомлением
        redirect_back(fallback_location: home_path, flash: { error: 'У вас нет прав на согласование трудозатрат, если есть такая необходимость, обратитесь к администратору' })
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
        Rails.logger.warn("TimeApprovalsController: unable to adjust columns - #{e.class}: #{e.message}") if defined?(Rails)
      end
    end
    unapproved_scope = time_entry_scope.
      preload(:issue => [:project, :tracker, :status, :assigned_to, :priority]).
      preload(:project, :user, :activity, :custom_values => :custom_field)
    @unapproved_dates = unapproved_scope.reorder(nil).distinct.pluck(:spent_on)

    # Показываем в списке все трудозатраты, но только по датам, где есть несогласованные
    @query.filters.delete('cf_2') if @query && @query.filters

    list_scope = time_entry_scope.
      preload(:issue => [:project, :tracker, :status, :assigned_to, :priority]).
      preload(:project, :user, :activity, :custom_values => :custom_field)
    list_scope = @unapproved_dates.present? ? list_scope.where(:spent_on => @unapproved_dates) : list_scope.none
    chart_scope = unapproved_scope

    # Итоги по дням на каждого пользователя: согласовано/требуется согласование/дефицит
    @user_daily_stats = []
    if @unapproved_dates.present?
      approved_cf = TimeEntryCustomField.find_by(id: 2) rescue nil
      is_approved = lambda do |entry|
        return false unless approved_cf
        cv = entry.custom_values&.detect { |v| v.custom_field_id == approved_cf.id }
        return false unless cv
        val = cv.value
        val == true || val == '1' || val.to_s.strip.downcase.in?(['true','t','yes','y','да','1'])
      end

      get_day_plan = lambda do |date|
        case date.wday
        when 1, 2, 3, 4
          8.67
        when 5
          5.17
        else
          0.0
        end
      end

      daily_data_by_user = Hash.new { |h, k| h[k] = Hash.new { |hh, kk| hh[kk] = { approved: 0.0, unapproved: 0.0 } } }
      users_with_unapproved = {}

      list_scope.to_a.each do |entry|
        user = entry.user
        next unless user
        date = entry.spent_on.to_date
        hours = entry.hours.to_f
        if is_approved.call(entry)
          daily_data_by_user[user.id][date][:approved] += hours
        else
          daily_data_by_user[user.id][date][:unapproved] += hours
          users_with_unapproved[user.id] = user.name
        end
      end

      @user_daily_stats = users_with_unapproved.keys.sort_by { |uid| users_with_unapproved[uid].to_s }.map do |user_id|
        user_name = users_with_unapproved[user_id]
        user_days = daily_data_by_user[user_id]
        dates = user_days.keys.sort

        {
          user_name: user_name,
          dates: dates.map { |d| d.strftime('%Y-%m-%d') },
          chart_data: dates.map do |date|
            approved = user_days[date][:approved].round(2)
            unapproved = user_days[date][:unapproved].round(2)
            total = approved + unapproved
            deficit = [get_day_plan.call(date) - total, 0.0].max.round(2)
            {
              date: date.strftime('%Y-%m-%d'),
              approved: approved,
              unapproved: unapproved,
              deficit: deficit
            }
          end
        }
      end
    end

    respond_to do |format|
      format.html do
        @entry_count = list_scope.count
        @entry_pages = Paginator.new @entry_count, per_page_option, params['page']
        @entries = list_scope.offset(@entry_pages.offset).limit(@entry_pages.per_page).to_a

        # Build activity distribution (pie) using the full filtered scope, not just current page
        activity_buckets = {}
        chart_scope.to_a.each do |time_entry|
          activity_id = time_entry.activity_id
          activity_name = time_entry.activity&.name || l(:label_none)
          bucket = (activity_buckets[activity_id] ||= { activity_id: activity_id, name: activity_name, value: 0.0 })
          bucket[:value] += time_entry.hours.to_f
        end
        @activity_pie_series = activity_buckets.values.map { |b| b.merge(value: b[:value].round(2)) }.
          sort_by { |item| -item[:value].to_f }

        # Weekly totals based on the current filtered scope but limited to the computed week range
        week_entries = chart_scope.where(:spent_on => @week_from..@week_to).to_a
        @week_total_hours = week_entries.sum { |e| e.hours.to_f }.round(2)
        @week_remaining_hours = [(@week_planned_hours - @week_total_hours).round(2), 0.0].max
        @week_completion_percent = (@week_planned_hours > 0 ? ((@week_total_hours / @week_planned_hours) * 100.0) : 0.0).round(1)

        # User memberships with roles
        @user_memberships = User.current.memberships.includes(:project, :roles).map do |m|
          { project: m.project&.name, roles: m.roles.map(&:name) }
        end.compact

        # Prepare data for individual user charts
        user_date_data = {}
        chart_scope.includes(:user).each do |time_entry|
          user_name = time_entry.user&.name || 'Unknown'
          date_str = time_entry.spent_on.strftime('%d.%m.%Y')
          
          user_date_data[user_name] ||= {}
          user_date_data[user_name][date_str] ||= []
          
          user_date_data[user_name][date_str] << {
            id: time_entry.id,
            hours: time_entry.hours.to_f,
            activity: time_entry.activity&.name || 'No Activity',
            activity_id: time_entry.activity_id,
            spent_on: time_entry.spent_on,
            comments: time_entry.comments
          }
        end

        # Convert to chart format: separate chart data for each user
        @user_charts = []
        
        # Sort users
        sorted_users = user_date_data.keys.sort
        
        sorted_users.each do |user_name|
          dates = user_date_data[user_name].keys.sort_by { |d| Date.strptime(d, '%d.%m.%Y') }
          
          user_chart_data = {
            user_name: user_name,
            dates: [],
            chart_data: []
          }
          
          dates.each do |date_str|
            entries = user_date_data[user_name][date_str]
            total_hours = entries.sum { |e| e[:hours] }.round(2)
            
            user_chart_data[:dates] << date_str
            user_chart_data[:chart_data] << {
              date: date_str,
              total_hours: total_hours,
              entries: entries.map do |entry|
                {
                  id: entry[:id],
                  hours: entry[:hours],
                  activity: entry[:activity],
                  activity_id: entry[:activity_id],
                  spent_on: entry[:spent_on].strftime('%d.%m.%Y'),
                  comments: entry[:comments]&.truncate(50) || ''
                }
              end
            }
          end
          
          @user_charts << user_chart_data
        end

        render :layout => !request.xhr?
      end
      format.api do
        @entry_count = list_scope.count
        @offset, @limit = api_offset_and_limit
        @entries = list_scope.offset(@offset).limit(@limit).preload(:custom_values => :custom_field).to_a
      end
      format.atom do
        entries = list_scope.limit(Setting.feeds_limit.to_i).reorder("#{TimeEntry.table_name}.created_on DESC").to_a
        render_feed(entries, :title => l(:label_spent_time))
      end
      format.csv do
        entries = list_scope.to_a
        send_data(query_to_csv(entries, @query, params), :type => 'text/csv; header=present', :filename => "#{filename_for_export(@query, 'timelog')}.csv")
      end
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

    # Базовые фильтры/колонки как в примере:
    # - cf_2 != 0
    # - subproject_id != * (исключить трудозатраты подпроектов)
    params[:f] = ['cf_2', 'subproject_id', '']
    params[:op] = {'cf_2' => '!', 'subproject_id' => '!*'}
    params[:v] = {
      'cf_2' => ['1']
    }

    params[:c] = ['spent_on','activity','cf_1','comments','hours']
    params[:group_by] ||= 'user'
    params[:t] ||= ['hours']
  end
end





