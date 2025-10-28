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
        
        # Переопределяем метод retrieve_time_entry_query для добавления данных графика
        alias_method :retrieve_time_entry_query_without_calendar, :retrieve_time_entry_query unless method_defined?(:retrieve_time_entry_query_without_calendar)
        
        def retrieve_time_entry_query
          result = retrieve_time_entry_query_without_calendar
          
          # Добавляем данные для календарного графика после установки @query
          if request.format.html? && @query
            surv_prepare_calendar_chart_data
          end
          
          result
        end
        
        private
        
        def surv_prepare_calendar_chart_data
          return unless @query
          
          begin
            scope = time_entry_scope
            @calendar_chart_data = prepare_calendar_chart_data(scope)
          rescue => e
            Rails.logger.error("[SurvStats] Failed to prepare calendar data: #{e.class}: #{e.message}")
            @calendar_chart_data = { daily_data: [], date_range: [] }
          end
        end
        
        def prepare_calendar_chart_data(scope)
          return {} unless scope
          
          # Получаем полный scope с предзагрузкой custom_values
          full_scope = scope.preload(:custom_values => :custom_field)
          
          # Находим custom field для согласования (id=2)
          approved_cf = TimeEntryCustomField.find_by(id: 2) rescue nil
          
          # Хелпер для проверки согласованности
          is_approved = lambda do |entry|
            return false unless approved_cf
            cv = entry.custom_values&.detect { |v| v.custom_field_id == approved_cf.id }
            return false unless cv
            val = cv.value
            val == true || val == '1' || val.to_s.strip.downcase.in?(['true','t','yes','y','да','1'])
          end
          
          # Получаем все записи
          all_entries = full_scope.to_a
          
          # Группируем по датам
          daily_data = Hash.new { |h, k| h[k] = { approved: 0.0, unapproved: 0.0 } }
          
          all_entries.each do |entry|
            date = entry.spent_on.to_date
            hours = entry.hours.to_f
            
            if is_approved.call(entry)
              daily_data[date][:approved] += hours
            else
              daily_data[date][:unapproved] += hours
            end
          end
          
          # Функция для вычисления планового времени на день
          get_day_plan = lambda do |date|
            case date.wday
            when 1, 2, 3, 4  # Понедельник-Четверг
              8.67
            when 5  # Пятница
              5.33
            else  # Выходные
              0.0
            end
          end
          
          # Создаем массив данных для календаря
          # format: [["2025-09-15", approved, unapproved, deficit, is_empty], ...]
          # approved - согласованные часы
          # unapproved - несогласованные часы
          # deficit - осталось распределить (план - факт, но не менее 0)
          # is_empty - флаг пустого дня (true если нет данных и это не выходной)
          
          date_range = daily_data.keys.minmax
          calendar_data = []
          
          # Генерируем данные для всех дней в диапазоне
          if date_range.is_a?(Array) && date_range.length == 2
            (date_range[0]..date_range[1]).each do |date|
              if daily_data.has_key?(date)
                # День с данными
                data = daily_data[date]
                total = data[:approved] + data[:unapproved]
                plan = get_day_plan.call(date)
                deficit = [plan - total, 0.0].max.round(2)
                
                calendar_data << [
                  date.strftime('%Y-%m-%d'),
                  data[:approved].round(2),
                  data[:unapproved].round(2),
                  deficit,
                  false  # не пустой
                ]
              else
                # День без данных - помечаем как пустой если это рабочий день
                is_empty = (1..5).include?(date.wday)  # Пн-Пт
                plan = get_day_plan.call(date)
                
                calendar_data << [
                  date.strftime('%Y-%m-%d'),
                  0.0,
                  0.0,
                  plan,  # весь план как deficit
                  is_empty
                ]
              end
            end
          else
            # Fallback на старую логику
            calendar_data = daily_data.map do |date, data|
              total = data[:approved] + data[:unapproved]
              plan = get_day_plan.call(date)
              deficit = [plan - total, 0.0].max.round(2)
              
              [
                date.strftime('%Y-%m-%d'),
                data[:approved].round(2),
                data[:unapproved].round(2),
                deficit,
                false
              ]
            end
          end
          
          {
            daily_data: calendar_data,
            date_range: date_range
          }
        end
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


