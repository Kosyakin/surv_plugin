document.addEventListener('DOMContentLoaded', function() {
    // Конфигурация идентификаторов пользовательских полей Redmine.
    const CUSTOM_FIELD_CONTRACT_ID = 'time_entry_custom_field_values_1';

    // Отключает стили плагина на страницах со списком трудозатрат, чтобы не ломать таблицы
    function disableStylesOnListPages() {
        // Если на странице есть таблица списка трудозатрат, отключаем стили плагина
        const hasListTable = document.querySelector('table.list.time-entries');
        if (hasListTable) {
            const links = document.querySelectorAll('link[rel="stylesheet"]');
            links.forEach(link => {
                const href = link.getAttribute('href') || '';
                if (
                    href.indexOf('/plugin_assets/redmine_modern_time_entries/stylesheets/modern_time_entries.css') !== -1 ||
                    href.indexOf('/plugin_assets/surv_time_entries_editing/stylesheets/modern_time_entries.css') !== -1
                ) {
                    try { link.disabled = true; } catch(e) { link.setAttribute('media', 'not all'); }
                }
            });
        }
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

     // Инициализирует Select2 для полей с поиском
    function initSelect2Fields(form) {
        const contractField = form.querySelector('#time_entry_custom_field_values_1');
        const activityField = form.querySelector('#time_entry_activity_id');
        
        if (contractField && !contractField.classList.contains('select2-hidden-accessible')) {
            $(contractField).select2({
                language: 'ru',
                placeholder: 'Выберите подтип деятельности',
                allowClear: true,
                width: '100%'
            });
        }
        
        if (activityField && !activityField.classList.contains('select2-hidden-accessible')) {
            $(activityField).select2({
                language: 'ru',
                placeholder: 'Выберите деятельность',
                allowClear: false,
                width: '100%'
            });
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

    // Создает одну колонку барабана (часы или минуты)
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

        // Инициализация после вставки в DOM (чтобы корректно вычислить высоту элементов)
        setTimeout(updateActive, 0);

        return {
            element: col,
            getValue: () => values[index],
            setValue: (v) => { const i = values.indexOf(v); if (i >= 0) { index = i; updateActive(); } }
        };
    }

    // Подключает барабан выбора времени к полю часов
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

        // При сабмите переносим выбранное значение в скрытое поле часов
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
        if (!date) return;
        try {
            if (typeof window.getTimeEntriesForDate === 'function') {
                window.getTimeEntriesForDate(date, userId, projectId);
            }
        } catch(e) {
            // Безопасный no-op: страница может не подключать график
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

        // Инициализируем Select2 для поля "Подтип деятельности"
        if (typeof $ !== 'undefined' && $.fn && $.fn.select2) {
            initSelect2Fields(form);
        } else {
            // Если Select2 еще не загружен, ждем его
            const checkSelect2 = setInterval(() => {
                if (typeof $ !== 'undefined' && $.fn && $.fn.select2) {
                    clearInterval(checkSelect2);
                    initSelect2Fields(form);
                }
            }, 100);
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
    
    // Также инициализируем при динамических изменениях формы
    if (typeof Turbolinks !== 'undefined') {
        document.addEventListener('turbolinks:render', function() {
            setTimeout(initEnhancements, 100);
        });
    }
});