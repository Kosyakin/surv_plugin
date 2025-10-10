document.addEventListener('DOMContentLoaded', function() {
    // --- Конфигурируемые параметры ---
    // ID активности, при выборе которой отображается поле "Подтип трудозатрат"
    const ACTIVITY_ID_FOR_CONTRACT_FIELD = '1'; // <-- Измените этот ID!

    // ID пользовательского поля "Подтип трудозатрат"
    const CUSTOM_FIELD_CONTRACT_ID = 'time_entry_custom_field_values_1';

    // ID пользовательского поля "Статус" (скрыто через CSS, но полезно для справки)
    const CUSTOM_FIELD_STATUS_ID = 'time_entry_custom_field_values_53';

    // ID пользовательского поля "Рабочая неделя" (скрыто через CSS, но полезно для справки)
    const CUSTOM_FIELD_WEEK_ID = 'time_entry_custom_field_values_56';

    // ID пользовательского поля "Месяц" (скрыто через CSS, но полезно для справки)
    const CUSTOM_FIELD_MONTH_ID = 'time_entry_custom_field_values_57';
    // --- Конец конфигурируемых параметров ---

    function disableStylesOnListPages() {
        // Если на странице есть таблица списка трудозатрат, отключаем стили плагина
        const hasListTable = document.querySelector('table.list.time-entries');
        if (hasListTable) {
            const links = document.querySelectorAll('link[rel="stylesheet"]');
            links.forEach(link => {
                const href = link.getAttribute('href') || '';
                if (href.indexOf('/plugin_assets/redmine_modern_time_entries/stylesheets/modern_time_entries.css') !== -1) {
                    try { link.disabled = true; } catch(e) { link.setAttribute('media', 'not all'); }
                }
            });
        }
    }

    function initEnhancements() {
        // Сначала обработаем условие отключения стилей на страницах со списком
        disableStylesOnListPages();

        // Проверяем, на странице создания/редактирования трудозатрат
        let newTimeEntryForm = document.getElementById('new_time_entry');
        let editTimeEntryForm = document.querySelector('.edit_time_entry');
        // Фолбэк: если классы/id нестандартные, попробуем найти форму по полю часов
        if (!newTimeEntryForm && !editTimeEntryForm) {
            const hoursEl = document.getElementById('time_entry_hours');
            const anyForm = hoursEl ? (hoursEl.closest('form') || null) : null;
            if (!anyForm) {
                return;
            }
            // Назначим как new по-умолчанию
            newTimeEntryForm = anyForm;
        }

        // Обрабатываем обе возможные формы
        enhanceForm(newTimeEntryForm);
        enhanceForm(editTimeEntryForm);
    }

    // Функции для обработки текста со скобками
    function extractParenthesesContent(text) {
        const match = text.match(/^(.+?)\s*\(([^)]+)\)\s*$/);
        if (match) {
            return {
                mainText: match[1].trim(),
                parenthesesText: match[2].trim(),
                hasParentheses: true
            };
        }
        return {
            mainText: text,
            parenthesesText: '',
            hasParentheses: false
        };
    }

    // Функция для преобразования select в комбинированное поле
    function convertSelectToCombo(selectElement) {
        if (!selectElement) return;

        const container = document.createElement('div');
        container.className = 'combo-select-container';

        const input = document.createElement('input');
        input.type = 'text';
        input.className = 'combo-select-input';
        input.placeholder = 'Введите или выберите значение';

        const dropdown = document.createElement('div');
        dropdown.className = 'combo-select-dropdown';

        // Создаем обертку для всего поля (включая подсказку)
        const fieldWrapper = document.createElement('div');
        fieldWrapper.className = 'combo-field-wrapper';

        // Создаем элемент для подсказки (отдельно от combo-контейнера)
        const tooltip = document.createElement('div');
        tooltip.className = 'combo-select-tooltip';
        tooltip.style.display = 'none';

        const originalSelect = selectElement.cloneNode(true);
        originalSelect.style.display = 'none';

        if (selectElement.value) {
            // Ищем выбранный option безопасно, без querySelector (значение может содержать кавычки)
            let selectedText = '';
            for (const opt of selectElement.options) {
                if (opt.value === selectElement.value) { selectedText = opt.textContent; break; }
            }
            if (selectedText) { 
                const parsed = extractParenthesesContent(selectedText);
                input.value = parsed.mainText;
                if (parsed.hasParentheses) {
                    tooltip.textContent = parsed.parenthesesText;
                    tooltip.style.display = 'block';
                }
            }
        }

        const options = [];
        let currentGroup = null;
        for (const option of selectElement.options) {
            const text = option.textContent || '';
            const isGroupLine = text.startsWith('--') && text.endsWith('--');
            if (isGroupLine) {
                currentGroup = text.replace(/^--|--$/g, '');
                options.push({ value: '', text: currentGroup, isGroup: true, groupName: currentGroup });
                continue;
            }
            if (option.value) {
                const parsed = extractParenthesesContent(text);
                options.push({
                    value: option.value,
                    text: text, // Оригинальный текст для отправки на сервер
                    displayText: parsed.mainText, // Текст для отображения
                    tooltipText: parsed.parenthesesText, // Текст для подсказки
                    hasParentheses: parsed.hasParentheses,
                    isGroup: false,
                    groupName: currentGroup
                });
            }
        }

        let allowedGroups = null; // null = без фильтра, иначе массив имен групп

        function updateDropdown(filter = '') {
            dropdown.innerHTML = '';
            let hasVisibleOptions = false;

            options.forEach(option => {
                const groupAllowed = !allowedGroups || (option.groupName && allowedGroups.includes(option.groupName));
                if (option.isGroup) {
                    if (!groupAllowed) return;
                    const groupElement = document.createElement('div');
                    groupElement.className = 'combo-select-option group';
                    groupElement.textContent = option.text.replace(/^--|--$/g, '');
                    dropdown.appendChild(groupElement);
                } else if (groupAllowed && (filter === '' || option.displayText.toLowerCase().includes(filter.toLowerCase()))) {
                    const optionElement = document.createElement('div');
                    optionElement.className = 'combo-select-option';
                    optionElement.textContent = option.displayText; // Показываем только основной текст
                    optionElement.dataset.value = option.value;
                    optionElement.dataset.originalText = option.text;
                    optionElement.dataset.displayText = option.displayText;
                    optionElement.dataset.tooltipText = option.tooltipText;
                    optionElement.dataset.hasParentheses = option.hasParentheses;

                    optionElement.addEventListener('mousedown', (e) => {
                        e.preventDefault();
                        input.value = option.displayText; // В поле ввода показываем только основной текст
                        originalSelect.value = option.value; // В скрытом select сохраняем оригинальное значение
                        
                        // Обновляем подсказку
                        if (option.hasParentheses) {
                            tooltip.textContent = option.tooltipText;
                            tooltip.style.display = 'block';
                        } else {
                            tooltip.style.display = 'none';
                        }
                        
                        container.classList.remove('expanded');
                    });

                    dropdown.appendChild(optionElement);
                    hasVisibleOptions = true;
                }
            });

            if (!hasVisibleOptions && filter !== '') {
                const noResults = document.createElement('div');
                noResults.className = 'combo-select-option';
                noResults.textContent = 'Совпадений не найдено';
                dropdown.appendChild(noResults);
            }
        }

        updateDropdown();

        // Открываем список по клику, а не по фокусу, чтобы не раскрываться при загрузке страницы с выбранным значением
        input.addEventListener('click', () => {
            container.classList.add('expanded');
            updateDropdown(input.value);
        });

        input.addEventListener('blur', () => {
            setTimeout(() => {
                container.classList.remove('expanded');
            }, 200);
        });

        input.addEventListener('input', (e) => {
            updateDropdown(e.target.value);

            const exactMatch = options.find(
                opt => !opt.isGroup && opt.displayText.toLowerCase() === e.target.value.toLowerCase()
            );

            if (exactMatch) {
                originalSelect.value = exactMatch.value;
                // Обновляем подсказку при точном совпадении
                if (exactMatch.hasParentheses) {
                    tooltip.textContent = exactMatch.tooltipText;
                    tooltip.style.display = 'block';
                } else {
                    tooltip.style.display = 'none';
                }
            } else {
                originalSelect.value = '';
                tooltip.style.display = 'none';
            }
        });

        input.addEventListener('keydown', (e) => {
            if (e.key === 'ArrowDown' || e.key === 'ArrowUp' || e.key === 'Enter') {
                e.preventDefault();

                const visibleOptions = Array.from(dropdown.querySelectorAll('.combo-select-option:not(.group)'));
                if (visibleOptions.length === 0) return;

                let highlighted = dropdown.querySelector('.combo-select-option.highlighted');

                if (e.key === 'Enter') {
                    if (highlighted) {
                        input.value = highlighted.dataset.displayText;
                        originalSelect.value = highlighted.dataset.value;
                        
                        // Обновляем подсказку
                        if (highlighted.dataset.hasParentheses === 'true') {
                            tooltip.textContent = highlighted.dataset.tooltipText;
                            tooltip.style.display = 'block';
                        } else {
                            tooltip.style.display = 'none';
                        }
                        
                        container.classList.remove('expanded');
                    }
                    return;
                }

                if (!highlighted) {
                    highlighted = visibleOptions[e.key === 'ArrowDown' ? 0 : visibleOptions.length - 1];
                    highlighted.classList.add('highlighted');
                } else {
                    const currentIndex = visibleOptions.indexOf(highlighted);
                    let newIndex = currentIndex;

                    if (e.key === 'ArrowDown') {
                        newIndex = (currentIndex + 1) % visibleOptions.length;
                    } else {
                        newIndex = (currentIndex - 1 + visibleOptions.length) % visibleOptions.length;
                    }

                    highlighted.classList.remove('highlighted');
                    highlighted = visibleOptions[newIndex];
                    highlighted.classList.add('highlighted');

                    highlighted.scrollIntoView({ block: 'nearest' });
                }
            }
        });

        // Собираем combo-контейнер
        container.appendChild(input);
        container.appendChild(dropdown);
        container.appendChild(originalSelect);

        // Собираем обертку поля
        fieldWrapper.appendChild(container);
        fieldWrapper.appendChild(tooltip);

        selectElement.parentNode.insertBefore(fieldWrapper, selectElement);
        selectElement.remove();

        // API для управления видимостью/фильтрацией
        function setEnabled(enabled) {
            input.readOnly = !enabled;
            container.classList.toggle('disabled', !enabled);
            fieldWrapper.classList.toggle('disabled', !enabled);
            if (!enabled) {
                originalSelect.setAttribute('disabled', 'disabled');
                tooltip.style.display = 'none';
            } else {
                originalSelect.removeAttribute('disabled');
            }
            if (!enabled) {
                input.value = '';
                originalSelect.value = '';
                tooltip.style.display = 'none';
            }
        }

        function setAllowedGroups(groups) {
            allowedGroups = Array.isArray(groups) && groups.length ? groups : null;
            updateDropdown(input.value || '');
        }

        function clearSelection() {
            input.value = '';
            originalSelect.value = '';
            tooltip.style.display = 'none';
            updateDropdown('');
        }

        function setValueByOptionValue(value) {
            if (!value) return false;
            const opt = options.find(o => !o.isGroup && o.value === value);
            if (!opt) return false;
            const groupAllowed = !allowedGroups || (opt.groupName && allowedGroups.includes(opt.groupName));
            if (!groupAllowed) return false;
            originalSelect.value = opt.value;
            input.value = opt.displayText;
            
            // Обновляем подсказку
            if (opt.hasParentheses) {
                tooltip.textContent = opt.tooltipText;
                tooltip.style.display = 'block';
            } else {
                tooltip.style.display = 'none';
            }
            
            return true;
        }

        return { container, fieldWrapper, input, dropdown, tooltip, originalSelect, setEnabled, setAllowedGroups, clearSelection, setValueByOptionValue };
    }

    // Вспомогательные функции для барабана часов/минут
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
        // Поддержка форматов: "H:MM", "H.MM" (десятичные часы), "H"
        const colon = value.match(/^\s*(\d{1,2})\s*[:h\-]?\s*(\d{1,2})\s*$/i);
        if (colon) {
            return clampTime(parseInt(colon[1], 10) || 0, parseInt(colon[2], 10) || 0);
        }
        const decimal = value.match(/^\s*(\d{1,2})(?:[\.,](\d{1,2}))?\s*$/);
        if (decimal) {
            const h = parseInt(decimal[1], 10) || 0;
            const frac = decimal[2] ? parseInt(decimal[2], 10) : 0;
            // Преобразуем десятичные в минуты (0..99 -> 0..59 масштабно)
            const minutes = Math.round((Math.min(frac, 99) / 100) * 60);
            return clampTime(h, minutes);
        }
        return { hours: 0, minutes: 0 };
    }

    function formatTimeString(hours, minutes) {
        const mm = String(minutes).padStart(2, '0');
        return `${hours}:${mm}`;
    }

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
                if (i === index) it.classList.add('active'); else it.classList.remove('active');
            });
            const itemHeight = items[0] ? items[0].offsetHeight : 0;
            list.style.transform = `translateY(${(1 - index) * itemHeight}px)`; // центрируем на средней позиции
            if (onChange) onChange(values[index]);
        }

        function step(delta) {
            const maxIndex = values.length - 1;
            index = Math.max(0, Math.min(maxIndex, index + delta));
            updateActive();
        }

        // Прокрутка колесиком
        col.addEventListener('wheel', (e) => {
            e.preventDefault();
            step(e.deltaY > 0 ? 1 : -1);
        }, { passive: false });

        // Клик по элементу списка
        list.addEventListener('click', (e) => {
            const li = e.target.closest('.drum-item');
            if (!li) return;
            const val = li.dataset.value;
            index = values.findIndex(v => String(v) === String(val));
            if (index < 0) index = 0;
            updateActive();
        });

        // Инициализация после вставки в DOM (чтобы была высота элементов)
        setTimeout(updateActive, 0);

        return {
            element: col,
            getValue: () => values[index],
            setValue: (v) => { const i = values.indexOf(v); if (i >= 0) { index = i; updateActive(); } }
        };
    }

    function attachDrumPickerToHours(form) {
        const hoursInput = form.querySelector('#time_entry_hours');
        if (!hoursInput) return;
        if (hoursInput.dataset.drumAttached === 'true') return; // не дублируем

        // Считываем текущее значение для инициализации
        const initial = parseTimeString(hoursInput.value);

        const wrapper = document.createElement('div');
        wrapper.className = 'drum-picker-wrapper';

        const labelHours = document.createElement('div');
        labelHours.className = 'drum-label';
        labelHours.textContent = 'Часы';
        const labelMinutes = document.createElement('div');
        labelMinutes.className = 'drum-label';
        labelMinutes.textContent = 'Минуты';

        const hoursValues = [0,1,2,3,4,5,6,7,8];
        const minutesValues = [0,10,20,30,40,50];

        let current = { hours: initial.hours, minutes: initial.minutes };

        function syncToInput() {
            const limited = clampTime(current.hours, current.minutes);
            current = limited;
            hoursPicker.setValue(current.hours);
            minutesPicker.setValue(current.minutes);
            // В упрощенной версии не меняем значение исходного инпута
        }

        function onHoursChange(h) {
            current.hours = Number(h);
            // если часы 8, ограничим минуты до 40
            if (current.hours === 8 && current.minutes > 40) current.minutes = 40;
            syncToInput();
        }
        function onMinutesChange(m) {
            current.minutes = Number(m);
            // если часы 8, ограничим минуты до 40
            if (current.hours === 8 && current.minutes > 40) current.minutes = 40;
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

        // Ничего не скрываем и не меняем атрибуты исходного инпута
        hoursInput.dataset.drumAttached = 'true';

        // Обертка для правильного выравнивания внутри <p>
        const container = document.createElement('div');
        container.className = 'drum-picker-container';
        container.appendChild(columns);

        // Подставим рядом с исходным инпутом
        hoursInput.parentNode.appendChild(container);

        // Скрываем исходное поле и убираем required
        try { hoursInput.type = 'hidden'; } catch(e) { hoursInput.style.display = 'none'; }
        if (hoursInput.hasAttribute('required')) hoursInput.removeAttribute('required');

        // Инициализируем значение скрытого инпута из барабана (с учетом ограничений)
        const initLimited = clampTime(current.hours, current.minutes);
        hoursInput.value = formatTimeString(initLimited.hours, initLimited.minutes);

        // При сабмите переносим выбранное значение в поле часов
        const formEl = form.tagName === 'FORM' ? form : form.closest('form');
        if (formEl) {
            formEl.addEventListener('submit', function() {
                const limited = clampTime(current.hours, current.minutes);
                hoursInput.value = formatTimeString(limited.hours, limited.minutes);
            });
        }
    }

    // Функция для получения трудозатрат по дате
    function getTimeEntriesForDate(date, userId, projectId) {
        if (!date) return;
        
        const params = new URLSearchParams({
            date: date,
            user_id: userId || '',
            project_id: projectId || ''
        });
        
        // Пробуем сначала timelog/for_date (более стабильно для Redmine), затем fallback на time_entries/for_date
        const urlPrimary = `/timelog/for_date?${params}`;
        const urlFallback = `/time_entries/for_date?${params}`;

        fetch(urlPrimary, {
            method: 'GET',
            headers: {
                'X-Requested-With': 'XMLHttpRequest',
                'Accept': 'application/json'
            }
        })
        .then(response => {
            if (!response.ok) {
                // Если 404 на первичном пути, пробуем fallback
                if (response.status === 404) {
                    return fetch(urlFallback, {
                        method: 'GET',
                        headers: {
                            'X-Requested-With': 'XMLHttpRequest',
                            'Accept': 'application/json'
                        }
                    });
                }
                throw new Error(`HTTP error! status: ${response.status}`);
            }
            return response.json();
        })
        .then(resOrData => resOrData && (typeof resOrData.json === 'function' ? resOrData.json() : resOrData))
        .then(data => {
            if (data.error) {
                alert(`Ошибка: ${data.error}`);
                return;
            }
            
            // Формируем сообщение для alert
            let message = `Трудозатраты на ${data.date}:\n`;
            message += `Всего часов: ${data.total_hours}\n`;
            message += `Количество записей: ${data.entries_count}\n\n`;
            
            if (data.entries && data.entries.length > 0) {
                message += 'Детали:\n';
                data.entries.forEach((entry, index) => {
                    message += `${index + 1}. ${entry.hours}ч - ${entry.activity_name} (ID: ${entry.activity_id})\n`;
                    if (entry.comments) {
                        message += `   Комментарий: ${entry.comments}\n`;
                    }
                    if (entry.project_name) {
                        message += `   Проект: ${entry.project_name}\n`;
                    }
                    if (entry.issue_subject) {
                        message += `   Задача: ${entry.issue_subject}\n`;
                    }
                    message += `   Время создания: ${entry.created_on}\n\n`;
                });
            } else {
                message += 'На эту дату трудозатрат не найдено.';
            }
            
            alert(message);
        })
        .catch(error => {
            console.error('Ошибка при получении трудозатрат:', error);
            alert('Ошибка при получении информации о трудозатратах');
        });
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
                    // Получаем ID пользователя
                    const userIdField = form.querySelector('#time_entry_user_id');
                    const userId = userIdField ? userIdField.value : '';
                    
                    // Получаем ID проекта
                    const projectIdField = form.querySelector('#time_entry_project_id');
                    const projectId = projectIdField ? projectIdField.value : '';
                    
                    // Получаем трудозатраты для выбранной даты
                    getTimeEntriesForDate(selectedDate, userId, projectId);
                }
            });
        }

        // Функционал скрытия/показа полей удален; используем только enable/disable + фильтрацию ниже
        const activitySelect = form.querySelector('#time_entry_activity_id');

        // Преобразуем select "Подтип деятельности" в комбинированное поле
        const contractSelect = form.querySelector(`#${CUSTOM_FIELD_CONTRACT_ID}`);
        let combo = null;
        if (contractSelect) {
            combo = convertSelectToCombo(contractSelect);
        }

        // Связка "Деятельность" -> "Подтип деятельности"
        if (activitySelect && combo) {
            const activityToGroups = {
                '': [],
                '1': ['Заявки', 'Договоры'],
                '2': ['Внепроектная работа для заказчика'],
                '3': ['Обеспечивающая деятельность'],
                '4': ['Согласованное отсутствие']
            };

            function applyActivityFilter() {
                const val = activitySelect.value || '';
                const groups = activityToGroups[val] || [];
                combo.setAllowedGroups(groups);
                const enabled = val !== '';
                combo.setEnabled(enabled);
                if (!enabled) {
                    combo.clearSelection();
                } else {
                    // Пытаемся восстановить выбранное значение, если оно разрешено
                    const currentVal = combo.originalSelect.value;
                    if (currentVal) {
                        const kept = combo.setValueByOptionValue(currentVal);
                        if (!kept) combo.clearSelection();
                    }
                }
            }

            applyActivityFilter();
            activitySelect.addEventListener('change', applyActivityFilter);
        }

        // Подключаем барабан к полю часов
        attachDrumPickerToHours(form);

        // При создании трудозатраты скрываем поле кастомное с id = 2 ("Согласовано")
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

        // Перемещаем поле комментария в самый низ формы (однократно)
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
            if (form && form.dataset) form.dataset.mtMovedComments = 'true';
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

    // Первая инициализация
    initEnhancements();

    // Повторная инициализация при полной загрузке (поддержка Turbolinks, если есть)
    document.addEventListener('turbolinks:load', initEnhancements, { once: true });
});