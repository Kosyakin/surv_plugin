# frozen_string_literal: true

class TimeApprovalsController < TimelogController
  # Разрешаем доступ всем авторизованным пользователям, проект не обязателен
  skip_before_action :authorize, only: :index
  skip_before_action :find_optional_project, only: :index
  before_action :require_login, only: :index
  before_action :find_project, only: :index
  before_action :apply_default_filters, only: :index

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

    # Compute weekly planned hours (Mon..Thu 8.67, Fri 5.33, weekend 0)
    weekly_dates = (@week_from..@week_to).to_a
    @week_planned_hours = weekly_dates.sum do |d|
      case d.wday
      when 1,2,3,4 then 8.67
      when 5 then 5.33
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

        # Weekly totals based on the current filtered scope but limited to the computed week range
        week_entries = scope.where(:spent_on => @week_from..@week_to).to_a
        @week_total_hours = week_entries.sum { |e| e.hours.to_f }.round(2)
        @week_remaining_hours = [(@week_planned_hours - @week_total_hours).round(2), 0.0].max
        @week_completion_percent = (@week_planned_hours > 0 ? ((@week_total_hours / @week_planned_hours) * 100.0) : 0.0).round(1)

        # User memberships with roles
        @user_memberships = User.current.memberships.includes(:project, :roles).map do |m|
          { project: m.project&.name, roles: m.roles.map(&:name) }
        end.compact

        # Prepare data for individual user charts
        user_date_data = {}
        scope.includes(:user).each do |time_entry|
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

  private

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

    params[:c] = ['spent_on','activity','cf_1','comments','cf_2','hours']
    params[:group_by] ||= 'user'
    params[:t] ||= ['hours']
  end
end





