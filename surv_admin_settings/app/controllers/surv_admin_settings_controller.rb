class SurvAdminSettingsController < ApplicationController
  layout 'admin'
  self.main_menu = false

  before_action :require_admin
  before_action :find_custom_field, only: [:list_management, :export_group, :upload_group_preview, :update_group]

  helper_method :custom_field_groups_options

  def index
    # Главная страница - только навигация
  end

  def closed_period
    @closed_period_date = Setting.plugin_surv_admin_settings['closed_period_date']
  end

  def update_closed_period
    closed_date = params.dig(:settings, :closed_period_date)
    Setting.plugin_surv_admin_settings = { 
      'closed_period_date' => closed_date
    }
    flash[:notice] = l(:notice_successful_update)
    redirect_to action: :closed_period
  end

  def list_management
    @selected_group = params[:selected_group]
    @preview_mode = params[:preview_mode] || (@current_values && @new_values)
  end

  def export_group
    group_name = params[:group]
    
    if group_name.present? && @custom_field
      group_values = get_group_values(@custom_field.possible_values, group_name)
      
      # Создаем CSV с UTF-8 и BOM
      csv_content = "\uFEFF" # BOM для UTF-8
      csv_content += CSV.generate(col_sep: "\t") do |csv|
        csv << ['Значения'] # Заголовок
        group_values.each do |value|
          csv << [value]
        end
      end
      
      filename = "#{group_name.gsub(/[^a-zA-Z0-9а-яА-Я]/, '_')}_#{Date.today}.csv"
      
      send_data csv_content,
                type: 'text/csv; charset=utf-8',
                filename: filename,
                disposition: 'attachment'
    else
      flash[:error] = l(:error_group_not_selected)
      redirect_to action: :list_management
    end
  end

  def upload_group_preview
    group_name = params[:group]
    uploaded_file = params[:csv_file]

    if group_name.blank? || uploaded_file.blank?
      flash[:error] = l(:error_group_file_required)
      redirect_to action: :list_management
      return
    end

    begin
      # Получаем текущие значения группы
      @current_values = get_group_values(@custom_field.possible_values, group_name)
      
      # Читаем и парсим CSV файл
      csv_content = File.read(uploaded_file.path, encoding: 'bom|utf-8')
      csv_content = csv_content.encode('UTF-8', invalid: :replace, undef: :replace)
      
      # Определяем разделитель
      delimiter = detect_delimiter(csv_content)
      
      # Парсим новые значения
      @new_values = []
      CSV.parse(csv_content, headers: true, col_sep: delimiter, encoding: 'UTF-8') do |row|
        value = row[0] || row['Значения'] # Первый столбец или столбец "Значения"
        @new_values << value if value.present?
      end
      
      # Убираем дубликаты
      @new_values.uniq!
      
      # Сохраняем все необходимые переменные для шаблона
      @selected_group = group_name
      @group_name = group_name
      @file_name = uploaded_file.original_filename
      @preview_mode = true
      
      # Рендерим страницу управления списками с данными предпросмотра
      render :list_management
      
    rescue CSV::MalformedCSVError => e
      flash[:error] = "Ошибка формата CSV файла: #{e.message}"
      redirect_to action: :list_management, selected_group: group_name
    rescue StandardError => e
      flash[:error] = "Ошибка обработки файла: #{e.message}"
      redirect_to action: :list_management, selected_group: group_name
    end
  end

  def update_group
    group_name = params[:group_name]
    new_values_json = params[:new_values]

    if group_name.blank? || new_values_json.blank?
      flash[:error] = l(:error_group_update_failed)
      redirect_to action: :list_management
      return
    end

    begin
      # Парсим новые значения из JSON
      new_values = JSON.parse(new_values_json)
      
      if @custom_field && group_name.present?
        # Обновляем значения в группе
        updated_values = replace_group_values(@custom_field.possible_values, group_name, new_values)
        
        if update_custom_field_values(updated_values)
          flash[:notice] = l(:notice_group_updated, count: new_values.size)
        else
          flash[:error] = l(:error_custom_field_update_failed)
        end
      else
        flash[:error] = l(:error_group_update_failed)
      end

    rescue JSON::ParserError
      flash[:error] = "Ошибка обработки данных"
    end

    redirect_to action: :list_management, selected_group: group_name
  end

  private

  def find_custom_field
    @custom_field = CustomField.find_by(id: 1)
  end

  def detect_delimiter(content)
    # Берем первую строку для анализа
    first_line = content.lines.first.to_s.chomp
    
    # Считаем количество различных разделителей
    delimiters = {
      "\t" => first_line.count("\t"),  # Tab
      ";"  => first_line.count(";"),   # Точка с запятой
      ","  => first_line.count(",")    # Запятая
    }
    
    # Выбираем разделитель с максимальным количеством вхождений
    best_delimiter = delimiters.max_by { |_, count| count }
    
    # Если нет явного лидера, используем точку с запятой по умолчанию
    if best_delimiter[1] > 0
      best_delimiter[0]
    else
      ";"
    end
  end

  def update_custom_field_values(new_values)
    @custom_field.possible_values = new_values
    @custom_field.save
  end

  def custom_field_groups_options
    return [] unless @custom_field&.possible_values
    
    groups = []
    
    @custom_field.possible_values.each do |value|
      if value.start_with?('--') && value.end_with?('--')
        groups << [value, value]
      end
    end
    
    groups
  end

  # Получить все значения указанной группы
  def get_group_values(all_values, group_name)
    group_values = []
    in_target_group = false
    
    all_values.each do |value|
      if value.start_with?('--') && value.end_with?('--')
        in_target_group = (value == group_name)
      elsif in_target_group
        group_values << value
      end
    end
    
    group_values
  end

  # Заменить значения в группе на новые
  def replace_group_values(all_values, group_name, new_values)
    result = []
    in_target_group = false
    group_processed = false
    
    all_values.each do |value|
      if value.start_with?('--') && value.end_with?('--')
        if value == group_name
          in_target_group = true
          group_processed = false
          result << value
        else
          in_target_group = false
          result << value
        end
      else
        if in_target_group && !group_processed
          # Добавляем новые значения вместо старых
          new_values.each { |new_val| result << new_val }
          group_processed = true
        elsif !in_target_group
          result << value
        end
        # Пропускаем старые значения целевой группы
      end
    end
    
    result
  end
end