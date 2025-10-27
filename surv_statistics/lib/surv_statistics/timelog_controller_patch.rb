require_dependency 'timelog_controller'

module SurvStatistics
  module TimelogControllerPatch
    def self.included(base)
      base.class_eval do
        unloadable

        before_action :surv_apply_default_time_filters, :only => [:index, :report]
        private :surv_apply_default_time_filters
      end
    end

    private

    # Applies default filters for HTML requests on timelog pages, clearing any URL-provided filters
    def surv_apply_default_time_filters
      return unless request.format && request.format.html?

      original = {
        f: params[:f], op: params[:op], v: params[:v], c: params[:c], t: params[:t],
        sort: params[:sort], query_id: params[:query_id], group_by: params[:group_by], columns: params[:columns]
      }
      Rails.logger.info("[SurvStats] Timelog before defaults: user_id=#{User.current.id} project_id=#{@project&.id} original=#{original.inspect}")

      # Clear any incoming filters/query selection from URL
      params[:f] = nil
      params[:op] = nil
      params[:v] = nil
      params[:c] = nil
      params[:t] = nil
      params[:sort] = nil
      params[:group_by] = nil
      params[:columns] = nil
      params[:query_id] = nil

      # Enforce default filters (aligned with ProjectsController#apply_default_time_filters)
      params[:set_filter] = '1'
      params[:sort] = 'spent_on:desc'

      params[:f] = ['spent_on', 'activity_id', 'cf_1', 'author_id', 'cf_2', '']
      params[:op] ||= {}
      params[:op][:spent_on] = 'lm'
      params[:op][:activity_id] = '='
      params[:op][:cf_1] = '*'
      params[:op][:author_id] = '*'
      params[:op][:cf_2] = '='

      params[:v] ||= {}
      params[:v][:activity_id] = ['1','2','3','4']
      params[:v][:cf_2] = ['1']

      # Columns, grouping and totals
      params[:c] = ['spent_on','cf_1','comments','cf_2','hours']
      params[:group_by] = 'activity'
      params[:t] = ['hours','']

      Rails.logger.info(
        "[SurvStats] Timelog defaults applied: set_filter=#{params[:set_filter]} sort=#{params[:sort]} " \
        "f=#{params[:f].inspect} op_keys=#{params[:op]&.keys.inspect} v_keys=#{params[:v]&.keys.inspect} " \
        "c=#{params[:c].inspect} group_by=#{params[:group_by].inspect} t=#{params[:t].inspect}"
      )
    end
  end
end

# Apply the patch
TimelogController.send(:include, SurvStatistics::TimelogControllerPatch)


