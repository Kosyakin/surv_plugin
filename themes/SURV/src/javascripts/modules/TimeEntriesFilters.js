var PurpleMine = PurpleMine || {} // eslint-disable-line no-use-before-define

PurpleMine.TimeEntriesFilters = (function () {
  'use strict'

  var instance
  var translations = {
    en: {
      filters: 'Filters',
      dateFrom: 'From',
      dateTo: 'To',
      user: 'User',
      activity: 'Activity',
      project: 'Project',
      apply: 'Apply'
    },
    ru: {
      filters: 'Фильтры',
      dateFrom: 'С',
      dateTo: 'По',
      user: 'Пользователь',
      activity: 'Активность',
      project: 'Проект',
      apply: 'Применить'
    }
  }

  function TimeEntriesFilters () {
    if (instance) {
      return instance
    }

    instance = this
    this.$sidebar = $('#sidebar')
    this.$content = $('#content')
    this.$filtersForm = null
    this.lang = document.documentElement.lang

    if (typeof translations[this.lang] === 'undefined') {
      this.lang = 'en'
    }

    this._ = translations[this.lang]

    if (this.isTimeEntriesPage()) {
      this.init()
    }
  }

  function isTimeEntriesPage () {
    return window.location.pathname.includes('/time_entries') ||
           window.location.pathname.includes('/time_entries/')
  }

  function buildFiltersForm () {
    var formHtml = '<form id="time_entries_scope_form" action="' + window.location.pathname + '" method="get">' +
      '<h3>' + instance._.filters + '</h3>' +
      '<p>' +
        '<label for="from_date">' + instance._.dateFrom + '</label>' +
        '<input type="date" name="from" id="from_date" value="">' +
      '</p>' +
      '<p>' +
        '<label for="to_date">' + instance._.dateTo + '</label>' +
        '<input type="date" name="to" id="to_date" value="">' +
      '</p>' +
      '<p>' +
        '<label for="user_filter">' + instance._.user + '</label>' +
        '<select name="user_id" id="user_filter">' +
          '<option value="">' + instance._.user + '</option>' +
        '</select>' +
      '</p>' +
      '<p>' +
        '<label for="activity_filter">' + instance._.activity + '</label>' +
        '<select name="activity_id" id="activity_filter">' +
          '<option value="">' + instance._.activity + '</option>' +
        '</select>' +
      '</p>' +
      '<p>' +
        '<input type="submit" value="' + instance._.apply + '" class="button-small">' +
      '</p>' +
    '</form>'

    return formHtml
  }

  function init () {
    if (instance.$sidebar.length > 0) {
      // Скрываем стандартные фильтры
      $('fieldset#filters').hide()
      
      // Добавляем форму фильтров в боковую панель
      var formHtml = buildFiltersForm()
      instance.$sidebar.prepend(formHtml)
      instance.$filtersForm = $('#time_entries_scope_form')
      
      // Настраиваем значения из URL параметров
      setFormValuesFromUrl()
      
      // Настраиваем обработчики событий
      bindEvents()
    }
  }

  function setFormValuesFromUrl () {
    var urlParams = new URLSearchParams(window.location.search)
    
    if (urlParams.get('from')) {
      $('#from_date').val(urlParams.get('from'))
    }
    
    if (urlParams.get('to')) {
      $('#to_date').val(urlParams.get('to'))
    }
    
    if (urlParams.get('user_id')) {
      $('#user_filter').val(urlParams.get('user_id'))
    }
    
    if (urlParams.get('activity_id')) {
      $('#activity_filter').val(urlParams.get('activity_id'))
    }
  }

  function bindEvents () {
    // Обработчик отправки формы
    instance.$filtersForm.on('submit', function (e) {
      e.preventDefault()
      
      var formData = new FormData(this)
      var params = new URLSearchParams()
      
      // Собираем параметры
      for (var pair of formData.entries()) {
        if (pair[1] !== '') {
          params.append(pair[0], pair[1])
        }
      }
      
      // Перенаправляем с новыми параметрами
      var newUrl = window.location.pathname
      if (params.toString()) {
        newUrl += '?' + params.toString()
      }
      
      window.location.href = newUrl
    })
  }

  TimeEntriesFilters.prototype.isTimeEntriesPage = isTimeEntriesPage
  TimeEntriesFilters.prototype.init = init

  return TimeEntriesFilters
})()

// Автоматическая инициализация
$(document).ready(function () {
  new PurpleMine.TimeEntriesFilters()
})
