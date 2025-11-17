class SurvAdminSettingsController < ApplicationController
  layout 'admin'
  self.main_menu = false

  before_action :require_admin
  before_action :find_custom_field, only: [:edit, :add_custom_field_value, :delete_custom_field_value, :export_group, :upload_group_preview, :update_group]

  helper_method :custom_field_groups_options

  def edit
    @closed_period_date = Setting.plugin_surv_admin_settings['closed_period_date']
    @csv_data = Setting.plugin_surv_admin_settings['csv_data'] || []
    @custom_field_values = @custom_field.possible_values if @custom_field
    
    # Загружаем данные предпросмотра если есть
    @group_preview_data = session[:group_preview_data]
    @selected_group = params[:selected_group] || @group_preview_data&.dig(:group_name)
  end

  def update
    closed_date = params.dig(:settings, :closed_period_date)
    Setting.plugin_surv_admin_settings = { 
      'closed_period_date' => closed_date,
      'csv_data' => Setting.plugin_surv_admin_settings['csv_data'] || []
    }
    flash[:notice] = l(:notice_successful_update)
    redirect_to action: :edit
  end

  def upload_csv
    uploaded_file = params[:csv_file]
    
    if uploaded_file && uploaded_file.original_filename.end_with?('.csv')
      begin
        csv_data = []
        
        # Читаем файл с определением кодировки
        csv_content = File.read(uploaded_file.path)
        
        # Пробуем определить кодировку и конвертировать в UTF-8
        detected_encoding = detect_encoding(csv_content)
        if detected_encoding && detected_encoding != 'UTF-8'
          csv_content = csv_content.force_encoding(detected_encoding).encode('UTF-8', invalid: :replace, undef: :replace)
        else
          csv_content = csv_content.force_encoding('UTF-8')
        end
        
        # Удаляем BOM если присутствует
        csv_content = remove_bom(csv_content)
        
        # Определяем разделитель
        delimiter = detect_delimiter(csv_content)
        
        # Парсим CSV с определенным разделителем
        CSV.parse(csv_content, headers: true, col_sep: delimiter, encoding: 'UTF-8') do |row|
          csv_data << row.to_hash
        end
        
        settings = Setting.plugin_surv_admin_settings || {}
        settings['csv_data'] = csv_data
        settings['last_upload_delimiter'] = delimiter
        Setting.plugin_surv_admin_settings = settings
        
        flash[:notice] = l(:notice_successful_upload, delimiter: delimiter == "\t" ? "табуляция" : delimiter)
      rescue CSV::MalformedCSVError => e
        flash[:error] = "Ошибка формата CSV файла: #{e.message}"
      rescue StandardError => e
        flash[:error] = "Ошибка обработки файла: #{e.message}"
      end
    else
      flash[:error] = "Пожалуйста, выберите CSV файл"
    end
    
    redirect_to action: :edit
  end

  def clear_csv
    settings = Setting.plugin_surv_admin_settings || {}
    settings['csv_data'] = []
    Setting.plugin_surv_admin_settings = settings
    
    flash[:notice] = l(:notice_successful_clear)
    redirect_to action: :edit
  end

  def export_custom_field
    custom_field_id = 1
    custom_field = CustomField.find_by(id: custom_field_id)
    
    if custom_field && custom_field.possible_values.any?
      all_values = custom_field.possible_values
      
      contracts = []
      requests = []
      current_group = nil
      
      all_values.each do |value|
        if value.start_with?('--') && value.end_with?('--')
          current_group = value
        else
          case current_group
          when '--Договоры--'
            contracts << value
          when '--Заявки--'
            requests << value
          end
        end
      end
      
      # Создаем CSV с UTF-8 и BOM
      csv_content = "\uFEFF" # BOM для UTF-8
      csv_content += CSV.generate(col_sep: "\t") do |csv|
        csv << ['Договоры', 'Заявки']
        
        max_length = [contracts.length, requests.length].max
        
        max_length.times do |i|
          contract_value = contracts[i] || ''
          request_value = requests[i] || ''
          csv << [contract_value, request_value]
        end
      end
      
      send_data csv_content,
                type: 'text/csv; charset=utf-8',
                filename: "contracts_requests_#{Date.today}.csv",
                disposition: 'attachment'
    else
      flash[:error] = l(:error_custom_field_not_found)
      redirect_to action: :edit
    end
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
      
      filename = "group_#{group_name.gsub(/[^a-zA-Z0-9]/, '_')}_#{Date.today}.csv"
      
      send_data csv_content,
                type: 'text/csv; charset=utf-8',
                filename: filename,
                disposition: 'attachment'
    else
      flash[:error] = l(:error_group_not_selected)
      redirect_to action: :edit
    end
  end
  def add_custom_field_value
    new_value = params[:new_value]
    group = params[:group]

    if new_value.present? && @custom_field
      current_values = @custom_field.possible_values.dup
      
      if group.present?
        # Добавляем значение в конкретную группу
        updated_values = insert_value_into_group(current_values, group, new_value)
      else
        # Добавляем значение в конец списка
        updated_values = current_values << new_value
      end

      if update_custom_field_values(updated_values)
        flash[:notice] = l(:notice_custom_field_value_added)
      else
        flash[:error] = l(:error_custom_field_update_failed)
      end
    else
      flash[:error] = l(:error_custom_field_value_blank)
    end

    redirect_to action: :edit
  end

  def delete_custom_field_value
    value_to_delete = params[:value]

    if value_to_delete.present? && @custom_field
      current_values = @custom_field.possible_values.dup
      updated_values = current_values.reject { |v| v == value_to_delete }

      if update_custom_field_values(updated_values)
        flash[:notice] = l(:notice_custom_field_value_deleted)
      else
        flash[:error] = l(:error_custom_field_update_failed)
      end
    else
      flash[:error] = l(:error_custom_field_value_blank)
    end

    redirect_to action: :edit
  end

  private

  def find_custom_field
    @custom_field = CustomField.find_by(id: 1)
  end

  def detect_encoding(content)
    # Простая проверка распространенных кодировок
    encodings = ['UTF-8', 'Windows-1251', 'CP1251', 'ISO-8859-5', 'UTF-16LE', 'UTF-16BE']
    
    encodings.each do |encoding|
      begin
        test_content = content.dup.force_encoding(encoding)
        if test_content.valid_encoding?
          # Дополнительная проверка для Windows-1251
          if encoding == 'Windows-1251' || encoding == 'CP1251'
            # Проверяем наличие кириллических символов
            if test_content =~ /[а-яА-Я]/
              return encoding
            end
          else
            return encoding
          end
        end
      rescue
        next
      end
    end
    
    # Если не удалось определить, возвращаем UTF-8 с заменой невалидных символов
    'UTF-8'
  end

  def remove_bom(content)
    # Удаляем BOM маркеры для разных кодировок
    bom_patterns = [
      "\xEF\xBB\xBF",    # UTF-8 BOM
      "\xFE\xFF",        # UTF-16 BE BOM
      "\xFF\xFE",        # UTF-16 LE BOM
      "\x00\x00\xFE\xFF", # UTF-32 BE BOM
      "\xFF\xFE\x00\x00"  # UTF-32 LE BOM
    ]
    
    bom_patterns.each do |bom|
      if content.start_with?(bom)
        content = content.byteslice(bom.bytesize..-1)
        break
      end
    end
    
    content
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

  def insert_value_into_group(values, group_name, new_value)
    # Находим индекс группы
    group_index = values.index(group_name)
    
    if group_index
      # Находим где заканчивается группа (до следующей группы или конца массива)
      next_group_index = nil
      values.each_with_index do |value, index|
        if index > group_index && value.start_with?('--') && value.end_with?('--')
          next_group_index = index
          break
        end
      end

      # Вставляем новое значение после группы, но перед следующей группой
      insert_index = next_group_index || values.size
      values.insert(insert_index, new_value)
    else
      # Если группа не найдена, добавляем в конец
      values << new_value
    end
    
    values
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
  # Метод для получения списка групп кастомного поля
  def custom_field_groups_options
    return [] unless @custom_field_values
    
    groups = []
    current_group = nil
    
    @custom_field_values.each do |value|
      if value.start_with?('--') && value.end_with?('--')
        current_group = value
        groups << [current_group, current_group]
      end
    end
    
    # Добавляем опцию "Без группы"
    groups.unshift([l(:label_no_group), ''])
    
    groups
  end
end