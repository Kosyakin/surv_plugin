(function() {
	function onReady(cb) {
		if (document.readyState === 'complete' || document.readyState === 'interactive') {
			cb();
		} else {
			document.addEventListener('DOMContentLoaded', cb);
		}
	}

	function isTimelogIndexPage() {
		var body = document.body;
		if (!body) return false;
		var cls = body.className || '';
		var byClass = /(^|\s)controller-timelog(\s|$)/.test(cls) && /(^|\s)action-index(\s|$)/.test(cls);
		if (byClass) return true;
		var path = (location.pathname || '').toLowerCase();
		return /\/projects\/.+\/time_entries$/.test(path) || /\/projects\/.+\/timelog$/.test(path);
	}

	function isVisible(el) {
		return !!(el && (el.offsetWidth || el.offsetHeight || el.getClientRects().length));
	}

	function applyLayout30(panel) {
		var content = document.getElementById('content');
		var sidebar = document.getElementById('sidebar');
		if (sidebar && isVisible(sidebar)) {
			sidebar.style.width = '30%';
			if (content) content.style.width = '70%';
			panel.style.width = '100%';
			return;
		}
		panel.style.float = 'right';
		panel.style.width = '30%';
		if (content) content.style.width = '70%';
	}

	function createPanel() {
		var sidebar = document.getElementById('sidebar');
		var container = document.createElement('div');
		container.id = 'ni-echarts-panel';
		container.style.border = '1px solid #ddd';
		container.style.borderRadius = '4px';
		container.style.margin = '0 0 12px 0';
		container.style.background = '#fff';

		var header = document.createElement('div');
		header.style.display = 'flex';
		header.style.alignItems = 'center';
		header.style.justifyContent = 'space-between';
		header.style.padding = '6px 8px';
		header.style.borderBottom = '1px solid #eee';
		header.style.cursor = 'pointer';

		var title = document.createElement('div');
		title.textContent = 'Трудозатраты (график)';
		title.style.fontWeight = '600';
		header.appendChild(title);

		var toggle = document.createElement('button');
		toggle.type = 'button';
		toggle.textContent = 'Свернуть';
		toggle.style.fontSize = '12px';
		toggle.style.padding = '3px 6px';
		toggle.style.border = '1px solid #ccc';
		toggle.style.borderRadius = '3px';
		toggle.style.background = '#f6f6f6';
		toggle.style.cursor = 'pointer';
		header.appendChild(toggle);

		var body = document.createElement('div');
		body.id = 'ni-echarts-body';
		body.style.height = '300px';
		body.style.padding = '6px';

		var chartEl = document.createElement('div');
		chartEl.id = 'ni-echarts-container';
		chartEl.style.width = '100%';
		chartEl.style.height = '100%';
		chartEl.style.minHeight = '220px';
		body.appendChild(chartEl);

		container.appendChild(header);
		container.appendChild(body);

		if (sidebar && isVisible(sidebar)) {
			sidebar.insertBefore(container, sidebar.firstChild);
		} else {
			var content = document.getElementById('content') || document.body;
			content.insertBefore(container, content.firstChild);
		}

		applyLayout30(container);
		return { container: container, header: header, toggle: toggle, body: body, chartEl: chartEl };
	}

	function normalizeHoursString(text) {
		if (!text) return '';
		var s = ('' + text).trim();
		s = s.replace(/\u00A0/g, ' ').replace(',', '.');
		s = s.replace(/[^0-9.\-]+/g, ' ');
		var tokens = s.split(/\s+/).filter(Boolean);
		if (!tokens.length) return '';
		return tokens[tokens.length - 1];
	}

	function parseHoursFlexible(text) {
		if (!text) return 0;
		var s = ('' + text).trim();
		var m = s.match(/(\d+)\s*:\s*(\d{1,2})/);
		if (m) {
			var h = parseInt(m[1], 10) || 0;
			var minutes = parseInt(m[2], 10) || 0;
			return h + (minutes / 60);
		}
		m = s.match(/(\d+)[\s\u00A0]*ч/i);
		var m2 = s.match(/(\d+)[\s\u00A0]*мин/i);
		if (m || m2) {
			var hh = m ? parseInt(m[1], 10) || 0 : 0;
			var mm = m2 ? parseInt(m2[1], 10) || 0 : 0;
			return hh + (mm / 60);
		}
		var decStr = normalizeHoursString(s);
		var dec = parseFloat(decStr);
		return isNaN(dec) ? 0 : dec;
	}

	function parseNumber(numStr) { var n = parseHoursFlexible(numStr); return isNaN(n) ? 0 : n; }

	function findTimelogTable() {
		var table = document.querySelector('table#time-entries')
			|| document.querySelector('div#time-entries table.list')
			|| document.querySelector('table.time-entries')
			|| document.querySelector('table.list.time-entries');
		if (table) return table;
		var candidates = Array.prototype.slice.call(document.querySelectorAll('table.list, table.time-entries, div#time-entries table'));
		for (var i = 0; i < candidates.length; i++) {
			var ths = candidates[i].querySelectorAll('thead th');
			for (var j = 0; j < ths.length; j++) {
				var t = (ths[j].textContent || '').trim().toLowerCase();
				if (/часы|hours/.test(t)) return candidates[i];
			}
		}
		return null;
	}

	function detectColumnIndexes(table) {
		var idxDate = -1, idxHours = -1;
		var headerCells = Array.prototype.slice.call(table.querySelectorAll('thead th'));
		for (var i = 0; i < headerCells.length; i++) {
			var th = headerCells[i];
			var text = (th.textContent || '').trim().toLowerCase();
			var cls = th.className || '';
			var dataCol = th.getAttribute('data-column') || '';
			if (idxDate === -1 && (/дата|date|spent_on/.test(text) || /\bdate\b|\bspent_on\b/.test(cls) || /date|spent_on/.test(dataCol))) idxDate = i;
			if (idxHours === -1 && (/часы|hours|spent/.test(text) || /\bhours\b|\bspent\b/.test(cls) || /hours|spent/.test(dataCol))) idxHours = i;
		}
		if (idxHours === -1 && headerCells.length) idxHours = headerCells.length - 1;
		if (idxDate === -1) idxDate = 0;
		return { idxDate: idxDate, idxHours: idxHours };
	}

	function parseDateToKey(text) {
		var s = ('' + text).trim().replace(/\u00A0/g, ' ');
		var m = s.match(/^(\d{1,2})[\.\/-](\d{1,2})[\.\/-](\d{4})$/);
		if (m) return m[3] + '-' + ('0'+m[2]).slice(-2) + '-' + ('0'+m[1]).slice(-2);
		m = s.match(/^(\d{4})-(\d{1,2})-(\d{1,2})$/);
		if (m) return m[1] + '-' + ('0'+m[2]).slice(-2) + '-' + ('0'+m[3]).slice(-2);
		m = s.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);
		if (m) return m[3] + '-' + ('0'+m[2]).slice(-2) + '-' + ('0'+m[1]).slice(-2);
		return null;
	}

	function extractHoursFromCell(td) {
		var node = td && (td.querySelector('.hours, .hours-int, .hours-dec') || td);
		var text = node ? (node.textContent || '').trim() : '';
		var val = parseHoursFlexible(text);
		if (val > 0) return val;
		var title = node && node.getAttribute ? node.getAttribute('title') : '';
		val = parseHoursFlexible(title);
		if (val > 0) return val;
		var last = td && td.lastChild && td.lastChild.textContent ? td.lastChild.textContent : '';
		return parseHoursFlexible(last);
	}

	function extractDataFromTable(table) {
		if (!table) return null;
		var indexes = detectColumnIndexes(table);
		var idxDate = indexes.idxDate, idxHours = indexes.idxHours;
		var mapByDate = {};
		var rows = Array.prototype.slice.call(table.querySelectorAll('tbody tr'));
		rows.forEach(function(row) {
			if (/total|итого/i.test(row.className || '')) return;
			var cells = row.children; if (!cells || cells.length === 0) return;
			var dateText = (cells[idxDate] && cells[idxDate].textContent) ? cells[idxDate].textContent.trim() : '';
			if (!dateText) { var dateCell = row.querySelector('td.spent_on, td.date'); if (dateCell) dateText = (dateCell.textContent || '').trim(); }
			var dateKey = parseDateToKey(dateText); if (!dateKey) return;
			var hours = extractHoursFromCell(cells[idxHours] || row.querySelector('td.hours'));
			if (!mapByDate[dateKey]) mapByDate[dateKey] = 0; mapByDate[dateKey] += hours;
		});
		var keys = Object.keys(mapByDate); keys.sort();
		return { keys: keys, labels: keys.map(function(k){ var p=k.split('-'); return p[2]+'.'+p[1]+'.'+p[0]; }), data: keys.map(function(k){ return +mapByDate[k].toFixed(2); }) };
	}

	function buildOptionFromData(parsed) {
		if (!parsed || !parsed.labels || !parsed.labels.length) return null;
		return { title: { text: 'Трудозатраты' }, tooltip: { trigger: 'axis' }, grid: { left: 40, right: 20, top: 40, bottom: 40 }, xAxis: { type: 'category', data: parsed.labels }, yAxis: { type: 'value', minInterval: 0.25 }, series: [{ name: 'Часы', type: 'bar', data: parsed.data, itemStyle: { color: '#3c8dbc' } }] };
	}

	function waitForEcharts(maxMs, cb) {
		var waited = 0; if (typeof echarts !== 'undefined') return cb();
		var iv = setInterval(function(){ waited += 50; if (typeof echarts !== 'undefined'){ clearInterval(iv); cb(); } else if (waited >= maxMs) { clearInterval(iv); } }, 50);
	}

	onReady(function() {
		if (!isTimelogIndexPage()) return;
		waitForEcharts(5000, function() {
			if (typeof echarts === 'undefined') return;
			var ui = createPanel();
			var chart = echarts.init(ui.chartEl);
			function resizeChart(){ chart.resize(); }
			var table = findTimelogTable();
			var parsed = extractDataFromTable(table);
			var option = buildOptionFromData(parsed) || { title: { text: 'Трудозатраты' }, xAxis: { type: 'category', data: [] }, yAxis: { type: 'value' }, series: [{ type: 'bar', data: [] }] };
			chart.setOption(option);
			setTimeout(resizeChart, 50);
			window.addEventListener('resize', resizeChart);

			var collapsed = false;
			function applyCollapsed(){ if (collapsed){ ui.body.style.display='none'; ui.toggle.textContent='Развернуть'; } else { ui.body.style.display=''; ui.toggle.textContent='Свернуть'; resizeChart(); } }
			ui.header.addEventListener('click', function(e){ if (e.target===ui.toggle || e.currentTarget===ui.header){ collapsed=!collapsed; applyCollapsed(); } });
			ui.toggle.addEventListener('click', function(e){ e.preventDefault(); e.stopPropagation(); collapsed=!collapsed; applyCollapsed(); });
			applyCollapsed();
		});
	});
})();

