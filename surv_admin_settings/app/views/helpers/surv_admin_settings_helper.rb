module SurvAdminSettingsHelper
  def custom_field_groups_options
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