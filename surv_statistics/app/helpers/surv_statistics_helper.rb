# Helper модуль для плагина статистики СУРВ
# Обеспечивает корректную фильтрацию трудозатрат в зависимости от прав пользователя
module SurvStatisticsHelper
  
  # Основной метод для получения отфильтрованного scope трудозатрат
  # Используется в представлениях для сбора статистики с учетом прав доступа
  # 
  # Фильтрация основана на праве согласования чужих трудозатрат:
  # - Если пользователь может согласовывать чужие записи - видит все
  # - Если не может согласовывать - видит только свои записи
  # 
  # @param options [Hash] опции для запроса (сортировка, лимиты и т.д.)
  # @return [ActiveRecord::Relation] отфильтрованный scope трудозатрат
  def time_entry_scope_with_visibility(options = {})
    scope = @query.results_scope(options)

    # Администраторы всегда видят всё
    return scope if User.current.admin?

    # Если нет проекта в контексте — перестрахуемся и покажем только свои записи
    return scope.where(user_id: User.current.id) unless @project

    # Определяем проекты текущей ветки, по которым у пользователя есть право согласования
    approvable_ids = surv_approvable_project_ids(@project)

    if approvable_ids.empty?
      # Во всей ветке нет прав на согласование → показываем только свои записи
      scope.where(user_id: User.current.id)
    else
      # Видим все записи по проектам, где есть право согласования,
      # и только свои записи по остальным проектам
      scope.where(
        "#{TimeEntry.table_name}.project_id IN (:projects) OR #{TimeEntry.table_name}.user_id = :uid",
        projects: approvable_ids,
        uid: User.current.id
      )
    end
  end

  private

  # Проверяет, нужно ли ограничить видимость трудозатрат только собственными записями
  # 
  # Логика работы:
  # 1. Для проектов с подпроектами - всегда показываем полную статистику (родительский уровень)
  # 2. Для проектов без подпроектов - проверяем право согласования чужих трудозатрат:
  #    - Если может согласовывать чужие записи (approve_time_entries = true) - видит ВСЕ
  #    - Если НЕ может согласовывать чужие записи (approve_time_entries = false) - видит ТОЛЬКО СВОИ
  # 
  # Это обеспечивает корректное отображение статистики на разных уровнях иерархии проектов
  # и соответствует бизнес-логике: кто может согласовывать, тот может видеть все данные
  # 
  # @return [Boolean] true если нужно ограничить видимость только своими записями
  def should_restrict_to_own_entries?
    return false unless @project
    return false if User.current.admin?

    # Если есть хотя бы один проект в ветке, где пользователь может согласовывать,
    # то для этих проектов ограничение не требуется.
    # Для остальных — показываем только свои записи.
    surv_approvable_project_ids(@project).empty?
  end

  # Кэшируем список проектов (текущий + потомки), где у пользователя есть право согласования
  def surv_approvable_project_ids(project)
    @surv_approvable_project_ids ||= {}
    @surv_approvable_project_ids[project.id] ||= begin
      project.self_and_descendants.select do |p|
        User.current.allowed_to?(:approve_time_entries, p)
      end.map(&:id)
    end
  end
end
