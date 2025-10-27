require_dependency 'timelog_controller'

#
# Патч к контроллеру учета трудозатрат (TimelogController)
# Задача:
#  - Принудительно задавать набор фильтров по умолчанию при открытии страниц учета
#    трудозатрат (index, report) в HTML-формате;
#  - Игнорировать параметры фильтрации, переданные в URL (сброс),
#    но делать исключение для фильтров "author_id" и пользовательского поля "cf_2"
#    ("Согласовано"): если они явно переданы в URL, то сохранять их; иначе —
#    устанавливать оператор "*" (то есть показать все значения);
#  - Вести логирование до и после применения дефолтов для диагностики.
#
# Почему патч, а не переписывание контроллера:
#  - В системе уже есть соседний плагин `surv_time_entries_editing`, который
#    применяет собственный патч к TimelogController. Прямое переопределение
#    контроллера конфликтовало бы с ним. Патч-инъекция через include —
#    стандартный путь Redmine для безопасного сосуществования нескольких плагинов.
#

module SurvStatistics
  module TimelogControllerPatch
    def self.included(base)
      base.class_eval do
        unloadable

        # Подключаем хук перед выполнением экшенов index и report
        # (ТОЛЬКО для HTML-запросов; см. проверку внутри метода)
        before_action :surv_apply_default_time_filters, :only => [:index, :report]
        private :surv_apply_default_time_filters
      end
    end

    private

    # Применяет дефолтные фильтры к страницам учета трудозатрат
    # Выполняется ТОЛЬКО для HTML-запросов. Предварительно сбрасывает любые
    # фильтры, пришедшие в URL, затем выставляет нужные дефолты. Исключение —
    # фильтры author_id и cf_2: если они переданы в URL, мы их сохраняем,
    # иначе ставим оператор "*" (показать все).
    def surv_apply_default_time_filters
      return unless request.format && request.format.html?
    
      # Сохраняем исходные параметры запроса
      original = {
        f: params[:f], op: params[:op], v: params[:v], c: params[:c], t: params[:t],
        sort: params[:sort], query_id: params[:query_id], group_by: params[:group_by], columns: params[:columns]
      }
      Rails.logger.info("[SurvStats] Timelog before defaults: user_id=#{User.current.id} project_id=#{@project&.id} original=#{original.inspect}")
    
      # Сбрасываем только сохраненный запрос
      params[:query_id] = nil
      params[:set_filter] = '1'
    
      # sort - устанавливаем только если не передан или пустой
      if params[:sort].blank? && params['sort'].blank?
        params[:sort] = 'spent_on:desc'
      end
    
      # Обработка фильтров - сохраняем все переданные, добавляем недостающие базовые
      if params[:f].nil? || !params[:f].is_a?(Array)
        # Если фильтров нет вообще - полная инициализация
        params[:f] = ['spent_on', 'activity_id', 'cf_1', 'author_id', 'cf_2', '']
        params[:op] ||= {}
        params[:op]['spent_on'] = 'lm'
        params[:op]['activity_id'] = '='
        params[:op]['cf_1'] = '*'
        params[:op]['author_id'] = '*'
        params[:op]['cf_2'] = '*'
    
        params[:v] ||= {}
        params[:v]['activity_id'] = ['1','2','3','4']
        params[:v]['author_id'] = ['']
        params[:v]['cf_2'] = ['']
      else
        # Если фильтры уже есть - добавляем только недостающие базовые
        params[:op] ||= {}
        params[:v] ||= {}
    
        # Базовые фильтры по умолчанию
        default_filters = {
          'spent_on' => { op: 'lm', v: nil }, # v не устанавливаем для дат
          'activity_id' => { op: '=', v: ['1','2','3','4'] },
          'cf_1' => { op: '*', v: [''] },
          'author_id' => { op: '*', v: [''] },
          'cf_2' => { op: '*', v: [''] }
        }
    
        default_filters.each do |field, config|
          unless params[:f].include?(field)
            params[:f] << field
            params[:op][field] = config[:op]
            params[:v][field] = config[:v] if config[:v]
          end
        end
    
        # Убедимся, что пустой элемент есть в массиве фильтров
        params[:f] << '' unless params[:f].include?('')
      end
    
      # Колонки для списка - устанавливаем только если не переданы или пустые
      if params[:c].blank? && params['c'].blank?
        params[:c] = ['spent_on','cf_1','comments','cf_2','hours']
      end
    
      # Группировка - устанавливаем только если не передана или пустая
      if params[:group_by].blank? && params['group_by'].blank?
        params[:group_by] = 'activity'
      end
    
      # Итоги - устанавливаем только если не переданы или пустые
      if params[:t].blank? && params['t'].blank?
        params[:t] = ['hours','']
      end
    
      Rails.logger.info(
        "[SurvStats] Timelog defaults applied: set_filter=#{params[:set_filter]} sort=#{params[:sort]} " \
        "f=#{params[:f].inspect} op_keys=#{params[:op]&.keys.inspect} v_keys=#{params[:v]&.keys.inspect} " \
        "c=#{params[:c].inspect} group_by=#{params[:group_by].inspect} t=#{params[:t].inspect}"
      )
    end
  end
end

# Подключаем патч к TimelogController
TimelogController.send(:include, SurvStatistics::TimelogControllerPatch)


