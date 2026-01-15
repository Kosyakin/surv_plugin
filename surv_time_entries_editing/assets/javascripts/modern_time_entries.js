document.addEventListener('DOMContentLoaded', function() {
    // Конфигурация идентификаторов пользовательских полей Redmine.
    const CUSTOM_FIELD_CONTRACT_ID = 'time_entry_custom_field_values_1';

    // Отключает стили плагина на страницах со списком трудозатрат, чтобы не ломать таблицы
    function disableStylesOnListPages() {
        const hasListTable = document.querySelector('table.list.time-entries');
        if (hasListTable) {
            const links = document.querySelectorAll('link[rel="stylesheet"]');
            links.forEach(link => {
                const href = link.getAttribute('href') || '';
                if (
                    href.includes('/plugin_assets/redmine_modern_time_entries/stylesheets/modern_time_entries.css') ||
                    href.includes('/plugin_assets/surv_time_entries_editing/stylesheets/modern_time_entries.css')
                ) {
                    try { 
                        link.disabled = true; 
                    } catch(e) { 
                        link.setAttribute('media', 'not all'); 
                    }
                }
            });
        }
    }

    // Маппинг активности к группам
    const activityToGroups = {
        '': [],
        '1': ['Заявки', 'Договоры'],
        '2': ['Внепроектная работа для заказчика'],
        '3': ['Обеспечивающая деятельность'],
        '4': ['Согласованное отсутствие']
    };

    // Функция для извлечения основной части текста (без скобок)
    function extractMainText(text) {
        if (!text) return '';
        // Удаляем все что в скобках (включая скобки)
        const mainText = text.replace(/\s*\([^)]*\)\s*$/, '').trim();
        return mainText || text;
    }

    // Функция для извлечения текста в скобках
    function extractBracketsText(text) {
        if (!text) return '';
        const match = text.match(/\(([^)]+)\)$/);
        return match ? match[1].trim() : '';
    }

    // Сохраняем оригинальные значения опций для восстановления
    function saveOriginalOptions() {
        const contractField = document.querySelector(`#${CUSTOM_FIELD_CONTRACT_ID}`);
        if (!contractField) return;
        
        // Сохраняем оригинальные тексты в data-атрибуты
        $(contractField).find('option').each(function() {
            const originalText = $(this).text();
            $(this).data('original-text', originalText);
        });
    }

    // Функция для скрытия/показа блока подтипа деятельности
    function toggleContractBlockVisibility(activityValue) {
        const contractField = document.querySelector(`#${CUSTOM_FIELD_CONTRACT_ID}`);
        if (!contractField) return;

        // Находим родительский <p> элемент для скрытия/показа
        const contractWrapper = contractField.closest('p');
        if (!contractWrapper) return;

        // Если деятельность не выбрана (пустая строка) или значение не в маппинге
        if (!activityValue || !activityToGroups[activityValue] || activityToGroups[activityValue].length === 0) {
            // Скрываем блок
            contractWrapper.style.display = 'none';
            // Очищаем значение в поле
            if (contractField.tagName === 'SELECT') {
                contractField.value = '';
            }
        } else {
            // Показываем блок
            contractWrapper.style.display = '';
            // Применяем фильтр к опциям
            filterContractOptionsByActivity(activityValue);
        }
    }

    // Функция для скрытия/показа опций на основе группы
    function filterContractOptionsByActivity(activityValue) {
        const contractField = document.querySelector(`#${CUSTOM_FIELD_CONTRACT_ID}`);
        if (!contractField) return;

        const allowedGroups = activityToGroups[activityValue] || [];
        
        // Показываем/скрываем опции в зависимости от группы
        $(contractField).find('option').each(function() {
            const optionText = $(this).text();
            const isGroupHeader = optionText.startsWith('--') && optionText.endsWith('--');
            
            if (isGroupHeader) {
                const groupName = optionText.replace(/^--|--$/g, '').trim();
                const shouldShow = allowedGroups.includes(groupName);
                
                if (shouldShow) {
                    $(this).show();
                    let nextElement = $(this).next();
                    while (nextElement.length && !(nextElement.text().startsWith('--') && nextElement.text().endsWith('--'))) {
                        nextElement.show();
                        nextElement = nextElement.next();
                    }
                } else {
                    $(this).hide();
                    let nextElement = $(this).next();
                    while (nextElement.length && !(nextElement.text().startsWith('--') && nextElement.text().endsWith('--'))) {
                        nextElement.hide();
                        nextElement = nextElement.next();
                    }
                }
            }
        });

        // Обновляем Select2 если он инициализирован
        if ($(contractField).data('select2')) {
            const currentValue = contractField.value;
            $(contractField).select2('destroy');
            initContractSelect2();
            // Восстанавливаем значение
            if (currentValue) {
                setTimeout(() => {
                    $(contractField).val(currentValue).trigger('change');
                }, 50);
            }
        }
    }

    // Инициализация Select2 для поля контракта
    function initContractSelect2() {
        const contractField = document.querySelector(`#${CUSTOM_FIELD_CONTRACT_ID}`);
        if (!contractField) return;
        
        // Сохраняем оригинальные опции
        saveOriginalOptions();
        
        // Получаем текущее значение ДО инициализации Select2
        const currentValue = contractField.value;
        const currentText = contractField.options[contractField.selectedIndex]?.text || '';
        
        $(contractField).select2({
            language: 'ru',
            placeholder: 'Выберите подтип деятельности',
            allowClear: true,
            width: '100%',
            escapeMarkup: function(markup) {
                return markup;
            },
            templateResult: function(data) {
                // Скрываем скрытые опции
                if (data.element && data.element.style.display === 'none') {
                    return null;
                }
                
                // Форматируем группы (жирный текст)
                if (data.text && data.text.startsWith('--') && data.text.endsWith('--')) {
                    const groupName = data.text.replace(/^--|--$/g, '');
                    return $('<span style="font-weight: bold; color: #666; background-color: #f0f0f0; display: block; padding: 8px 12px;">' + groupName + '</span>');
                }
                
                // Используем сохраненный оригинальный текст
                const originalText = $(data.element).data('original-text') || data.text;
                const mainText = extractMainText(originalText);
                const bracketsText = extractBracketsText(originalText);
                
                // Создаем контейнер для элемента
                const container = $('<div style="display: flex; flex-direction: column; padding: 10px 12px; min-height: 44px; justify-content: center;"></div>');
                
                // Основной текст
                const mainSpan = $('<span style="font-size: 14px; color: #333; line-height: 1.4;"></span>');
                mainSpan.text(mainText);
                container.append(mainSpan);
                
                // Если есть текст в скобках, добавляем его как подсказку
                if (bracketsText) {
                    const hintSpan = $('<span style="font-size: 12px; color: #666; line-height: 1.3; margin-top: 2px; font-style: italic;"></span>');
                    hintSpan.text(bracketsText);
                    container.append(hintSpan);
                }
                
                return container;
            },
            templateSelection: function(data) {
                // Для выбранного значения показываем только основную часть (без скобок)
                if (data.text && data.text.startsWith('--') && data.text.endsWith('--')) {
                    return '';
                }
                
                // Используем сохраненный оригинальный текст
                const originalText = $(data.element).data('original-text') || data.text;
                const mainText = extractMainText(originalText);
                return mainText || data.text;
            }
        });
        
        // После инициализации восстанавливаем значение
        if (currentValue) {
            setTimeout(() => {
                $(contractField).val(currentValue).trigger('change');
                
                // Вручную обновляем отображаемый текст
                const selectionSpan = document.querySelector(`#select2-${CUSTOM_FIELD_CONTRACT_ID}-container .select2-selection__rendered`);
                if (selectionSpan && currentText) {
                    const mainText = extractMainText(currentText);
                    selectionSpan.textContent = mainText;
                    selectionSpan.title = mainText;
                }
            }, 100);
        }
    }

    // Инициализирует Select2 для полей с поиском
    function initSelect2Fields(form) {
        const contractField = form.querySelector('#time_entry_custom_field_values_1');
        const activityField = form.querySelector('#time_entry_activity_id');
        
        // Инициализируем поле деятельности
        if (activityField && !activityField.classList.contains('select2-hidden-accessible')) {
            // Сохраняем оригинальные тексты для поля деятельности
            $(activityField).find('option').each(function() {
                $(this).data('original-text', $(this).text());
            });
            
            // Получаем текущее значение
            const currentActivityValue = activityField.value;
            const currentActivityText = activityField.options[activityField.selectedIndex]?.text || '';
            
            $(activityField).select2({
                language: 'ru',
                placeholder: 'Выберите деятельность',
                allowClear: false,
                width: '100%',
                templateResult: function(data) {
                    // Обрабатываем опции деятельности - убираем скобки
                    const originalText = $(data.element).data('original-text') || data.text;
                    const mainText = extractMainText(originalText);
                    return mainText || data.text;
                },
                templateSelection: function(data) {
                    // Для выбранного значения показываем только основную часть
                    const originalText = $(data.element).data('original-text') || data.text;
                    const mainText = extractMainText(originalText);
                    return mainText || data.text;
                }
            });
            
            // Восстанавливаем отображаемый текст для текущего значения
            if (currentActivityValue && currentActivityText) {
                setTimeout(() => {
                    const selectionSpan = document.querySelector(`#select2-${activityField.id}-container .select2-selection__rendered`);
                    if (selectionSpan) {
                        const mainText = extractMainText(currentActivityText);
                        selectionSpan.textContent = mainText;
                        selectionSpan.title = mainText;
                    }
                }, 100);
            }
            
            // Добавляем обработчик изменения деятельности
            $(activityField).on('change', function() {
                const activityValue = this.value;
                // Очищаем поле подтипа деятельности при изменении деятельности
                const contractField = document.querySelector(`#${CUSTOM_FIELD_CONTRACT_ID}`);
                if (contractField) {
                    if (contractField.tagName === 'SELECT') {
                        contractField.value = '';
                        // Если используется Select2, обновляем его
                        if ($(contractField).data('select2')) {
                            $(contractField).val('').trigger('change');
                        }
                    } else if (contractField.tagName === 'INPUT') {
                        contractField.value = '';
                    }
                }
                // Обновляем видимость блока подтипа деятельности
                toggleContractBlockVisibility(activityValue);
            });
            
            // Применяем начальное состояние при загрузке
            if (activityField.value) {
                setTimeout(() => toggleContractBlockVisibility(activityField.value), 100);
            } else {
                // Если деятельность не выбрана, скрываем блок подтипа
                toggleContractBlockVisibility('');
            }
        }
        
        // Инициализируем поле контракта
        if (contractField && !contractField.classList.contains('select2-hidden-accessible')) {
            initContractSelect2();
        }
    }

    // Вспомогательные функции для барабана выбора часов/минут
    function clampTime(hours, minutes) {
        let h = Math.max(0, Math.min(8, hours));
        let m = Math.max(0, Math.min(50, minutes));
        m = Math.round(m / 10) * 10;
        if (m === 60) { m = 50; }
        if (h === 8 && m > 40) { m = 40; }
        return { hours: h, minutes: m };
    }

    function parseTimeString(value) {
        if (!value) return { hours: 0, minutes: 0 };
        
        const colon = value.match(/^\s*(\d{1,2})\s*[:h\-]?\s*(\d{1,2})\s*$/i);
        if (colon) {
            return clampTime(parseInt(colon[1], 10) || 0, parseInt(colon[2], 10) || 0);
        }
        
        const decimal = value.match(/^\s*(\d{1,2})(?:[\.,](\d{1,2}))?\s*$/);
        if (decimal) {
            const h = parseInt(decimal[1], 10) || 0;
            const frac = decimal[2] ? parseInt(decimal[2], 10) : 0;
            const minutes = Math.round((Math.min(frac, 99) / 100) * 60);
            return clampTime(h, minutes);
        }
        
        return { hours: 0, minutes: 0 };
    }

    function formatTimeString(hours, minutes) {
        const mm = String(minutes).padStart(2, '0');
        return `${hours}:${mm}`;
    }

    // Создает одну колонку барабана
    function buildDrumColumn(values, initial, onChange) {
        const col = document.createElement('div');
        col.className = 'drum-column';

        const viewport = document.createElement('div');
        viewport.className = 'drum-viewport';

        const list = document.createElement('ul');
        list.className = 'drum-list';

        values.forEach(v => {
            const li = document.createElement('li');
            li.className = 'drum-item';
            li.textContent = typeof v === 'number' ? String(v).padStart(2, '0') : String(v);
            li.dataset.value = v;
            list.appendChild(li);
        });

        viewport.appendChild(list);
        col.appendChild(viewport);

        let index = Math.max(0, values.indexOf(initial));

        function updateActive() {
            const items = list.querySelectorAll('.drum-item');
            items.forEach((it, i) => {
                if (i === index) {
                    it.classList.add('active');
                } else {
                    it.classList.remove('active');
                }
            });
            const itemHeight = items[0] ? items[0].offsetHeight : 0;
            list.style.transform = `translateY(${(1 - index) * itemHeight}px)`;
            if (onChange) onChange(values[index]);
        }

        function step(delta) {
            const maxIndex = values.length - 1;
            index = Math.max(0, Math.min(maxIndex, index + delta));
            updateActive();
        }

        col.addEventListener('wheel', (e) => {
            e.preventDefault();
            step(e.deltaY > 0 ? 1 : -1);
        }, { passive: false });

        list.addEventListener('click', (e) => {
            const li = e.target.closest('.drum-item');
            if (!li) return;
            const val = li.dataset.value;
            index = values.findIndex(v => String(v) === String(val));
            if (index < 0) index = 0;
            updateActive();
        });

        setTimeout(updateActive, 0);

        return {
            element: col,
            getValue: () => values[index],
            setValue: (v) => { 
                const i = values.indexOf(v); 
                if (i >= 0) { 
                    index = i; 
                    updateActive(); 
                } 
            }
        };
    }

    // Подключает барабан выбора времени к полю часов
    function attachDrumPickerToHours(form) {
        const hoursInput = form.querySelector('#time_entry_hours');
        if (!hoursInput || hoursInput.dataset.drumAttached === 'true') return;

        const initial = parseTimeString(hoursInput.value);
        const wrapper = document.createElement('div');
        wrapper.className = 'drum-picker-wrapper';

        const labelHours = document.createElement('div');
        labelHours.className = 'drum-label';
        labelHours.textContent = 'Часы';
        const labelMinutes = document.createElement('div');
        labelMinutes.className = 'drum-label';
        labelMinutes.textContent = 'Минуты';

        const hoursValues = [0, 1, 2, 3, 4, 5, 6, 7, 8];
        const minutesValues = [0, 10, 20, 30, 40, 50];

        let current = { hours: initial.hours, minutes: initial.minutes };

        function syncToInput() {
            const limited = clampTime(current.hours, current.minutes);
            current = limited;
            hoursPicker.setValue(current.hours);
            minutesPicker.setValue(current.minutes);
        }

        function onHoursChange(h) {
            current.hours = Number(h);
            if (current.hours === 8 && current.minutes > 40) {
                current.minutes = 40;
            }
            syncToInput();
        }
        
        function onMinutesChange(m) {
            current.minutes = Number(m);
            if (current.hours === 8 && current.minutes > 40) {
                current.minutes = 40;
            }
            syncToInput();
        }

        const hoursPicker = buildDrumColumn(hoursValues, current.hours, onHoursChange);
        const minutesPicker = buildDrumColumn(minutesValues, current.minutes, onMinutesChange);

        const columns = document.createElement('div');
        columns.className = 'drum-columns';
        const colH = document.createElement('div');
        colH.className = 'drum-col';
        colH.appendChild(labelHours);
        colH.appendChild(hoursPicker.element);
        const colM = document.createElement('div');
        colM.className = 'drum-col';
        colM.appendChild(labelMinutes);
        colM.appendChild(minutesPicker.element);
        columns.appendChild(colH);
        columns.appendChild(colM);

        hoursInput.dataset.drumAttached = 'true';

        const container = document.createElement('div');
        container.className = 'drum-picker-container';
        container.appendChild(columns);

        hoursInput.parentNode.appendChild(container);

        try { 
            hoursInput.type = 'hidden'; 
        } catch(e) { 
            hoursInput.style.display = 'none'; 
        }
        
        if (hoursInput.hasAttribute('required')) {
            hoursInput.removeAttribute('required');
        }

        const initLimited = clampTime(current.hours, current.minutes);
        hoursInput.value = formatTimeString(initLimited.hours, initLimited.minutes);

        const formEl = form.tagName === 'FORM' ? form : form.closest('form');
        if (formEl) {
            formEl.addEventListener('submit', function() {
                const limited = clampTime(current.hours, current.minutes);
                hoursInput.value = formatTimeString(limited.hours, limited.minutes);
            });
        }
    }

    // Делегат для получения трудозатрат по дате
    function getTimeEntriesForDate(date, userId, projectId) {
        if (!date || typeof window.getTimeEntriesForDate !== 'function') return;
        try {
            window.getTimeEntriesForDate(date, userId, projectId);
        } catch(e) {
            // Безопасный no-op
        }
    }

    // Функция для обработки конкретной формы
    function enhanceForm(form) {
        if (!form) return;

        // Добавляем обработчик изменения даты
        const dateField = form.querySelector('#time_entry_spent_on');
        if (dateField) {
            dateField.addEventListener('change', function() {
                const selectedDate = this.value;
                if (selectedDate) {
                    const userIdField = form.querySelector('#time_entry_user_id');
                    const userId = userIdField ? userIdField.value : '';
                    
                    const projectIdField = form.querySelector('#time_entry_project_id');
                    const projectId = projectIdField ? projectIdField.value : '';
                    
                    getTimeEntriesForDate(selectedDate, userId, projectId);
                }
            });
        }

        // Инициализируем Select2 для полей
        if (typeof $ !== 'undefined' && $.fn && $.fn.select2) {
            initSelect2Fields(form);
        } else {
            const checkSelect2 = setInterval(() => {
                if (typeof $ !== 'undefined' && $.fn && $.fn.select2) {
                    clearInterval(checkSelect2);
                    initSelect2Fields(form);
                }
            }, 100);
        }

        // Подключаем барабан к полю часов
        attachDrumPickerToHours(form);

        // При создании трудозатраты скрываем поле "Согласовано"
        try {
            const isCreateForm = form && form.id === 'new_time_entry';
            if (isCreateForm) {
                const approvedField = form.querySelector('#time_entry_custom_field_values_2');
                if (approvedField) {
                    const wrapper = approvedField.closest('p');
                    if (wrapper) wrapper.style.display = 'none';
                }
            }
        } catch(e) { /* noop */ }

        // При редактировании трудозатраты скрываем поле "Проект", "Пользователь" и "Согласовано"
        try {
            const isEditForm = form && (form.classList.contains('edit_time_entry') || (form.id && form.id !== 'new_time_entry'));
            if (isEditForm) {
                // Скрываем поле "Проект"
                const projectField = form.querySelector('#time_entry_project_id');
                if (projectField) {
                    const projectWrapper = projectField.closest('p');
                    if (projectWrapper) projectWrapper.style.display = 'none';
                }
                
                // Скрываем поле "Пользователь"
                const userField = form.querySelector('#time_entry_user_id');
                if (userField) {
                    const userWrapper = userField.closest('p');
                    if (userWrapper) userWrapper.style.display = 'none';
                }
                
                // Скрываем поле "Согласовано" (cf_2)
                const approvedField = form.querySelector('#time_entry_custom_field_values_2');
                if (approvedField) {
                    const approvedWrapper = approvedField.closest('p');
                    if (approvedWrapper) approvedWrapper.style.display = 'none';
                }
            }
        } catch(e) { /* noop */ }

        // Перемещаем поле комментария в самый низ формы
        if (form && (!form.dataset || form.dataset.mtMovedComments !== 'true')) {
            try {
                const commentsEl = form.querySelector('#time_entry_comments');
                if (commentsEl) {
                    const commentsP = commentsEl.closest('p');
                    const box = form.querySelector('.box.tabular') || form;
                    if (commentsP && box && commentsP.parentElement) {
                        box.appendChild(commentsP);
                    }
                }
            } catch(e) { /* noop */ }
            if (form && form.dataset) {
                form.dataset.mtMovedComments = 'true';
            }
        }

        // Скрываем поле "Задача" целиком
        try {
            const issueInput = form.querySelector('#time_entry_issue_id');
            if (issueInput) {
                const issueP = issueInput.closest('p');
                if (issueP) issueP.style.display = 'none';
            }
            const issueSpan = form.querySelector('#time_entry_issue');
            if (issueSpan && issueSpan.closest('p')) {
                issueSpan.closest('p').style.display = 'none';
            }
        } catch(e) { /* noop */ }
    }

    // Инициализация улучшений на страницах создания/редактирования
    function initEnhancements() {
        // Сначала обработаем условие отключения стилей на страницах со списком
        disableStylesOnListPages();

        // Проверяем, на странице создания/редактирования трудозатрат
        let newTimeEntryForm = document.getElementById('new_time_entry');
        let editTimeEntryForm = document.querySelector('.edit_time_entry');
        
        // Фолбэк: если классы/id нестандартные, попробуем найти форму по полю часов
        if (!newTimeEntryForm && !editTimeEntryForm) {
            const hoursEl = document.getElementById('time_entry_hours');
            const anyForm = hoursEl ? hoursEl.closest('form') : null;
            if (anyForm) {
                newTimeEntryForm = anyForm;
            } else {
                return;
            }
        }

        // Обрабатываем обе возможные формы
        if (newTimeEntryForm) enhanceForm(newTimeEntryForm);
        if (editTimeEntryForm) enhanceForm(editTimeEntryForm);
    }

    // Первая инициализация
    initEnhancements();

    // Повторная инициализация при полной загрузке
    document.addEventListener('turbolinks:load', initEnhancements);
    
    // Также инициализируем при динамических изменениях формы
    if (typeof Turbolinks !== 'undefined') {
        document.addEventListener('turbolinks:render', function() {
            setTimeout(initEnhancements, 100);
        });
    }
});