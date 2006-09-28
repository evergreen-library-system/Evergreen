var oilsRptTemplateCache = {};
var oilsRptReportCache = {};

/* utility method to find and build the correct folder window object */
function oilsRptBuildFolderWindow( type, folderId ) {
	var node = oilsRptCurrentFolderManager.findNode(type, folderId);
	_debug('drawing folder window for folder ' + node.folder.name());
	switch(type) {
		case 'template': 
			return new oilsRptTemplateFolderWindow(node);
		case 'report':
			return new oilsRptReportFolderWindow(node);
		case 'output':
			return new oilsRptOutputFolderWindow(node);
	}
}

function oilsRptFetchTemplate(id) {
	if( oilsRptTemplateCache[id] )
		return oilsRptTemplateCache[id];
	var r = new Request(OILS_RPT_FETCH_TEMPLATE, SESSION, id);
	r.send(true);
	return oilsRptTemplateCache[id] = r.result();
}



/* generic folder window class */
oilsRptFolderWindow.prototype = new oilsRptObject();
oilsRptFolderWindow.prototype.constructor = oilsRptFolderWindow;
oilsRptFolderWindow.baseClass = oilsRptObject.prototype.constructor;
function oilsRptFolderWindow() { }
oilsRptFolderWindow.prototype.init2 = function(node, type) {
	this.folderNode = node;
	this.type = type;
	this.init();
}

oilsRptFolderWindow.prototype.openWindow = function(node) {
	hideMe(DOM.oils_rpt_template_folder_window_contents_div);	
	hideMe(DOM.oils_rpt_report_folder_window_contents_div);
	unHideMe(DOM.oils_rpt_folder_table_right_td);
	unHideMe(node);
}

oilsRptFolderWindow.prototype.fetchFolderData = function(type, selector, cache, callback) {
	removeChildren(selector);
	var req = new Request(OILS_RPT_FETCH_FOLDER_DATA, 
		SESSION, type, this.folderNode.folder.id());
	req.callback(
		function(r) {
			var ts = r.getResultObject();
			if(!ts) return;
			for( var i = 0; i < ts.length; i++ )  {
				var name = ts[i].name();
				if( type == 'report' ) 
					name = oilsRptFetchTemplate(ts[i].template()).name() + ' : ' + name;
				
				insertSelectorVal(selector, -1, name, ts[i].id());
				cache[ts[i].id()] = ts[i];
			}
			if(callback) callback();
		}
	);
	req.send();
}


oilsRptTemplateFolderWindow.prototype = new oilsRptFolderWindow();
oilsRptTemplateFolderWindow.prototype.constructor = oilsRptTemplateFolderWindow;
oilsRptTemplateFolderWindow.baseClass = oilsRptFolderWindow.prototype.constructor;
function oilsRptTemplateFolderWindow(node) { this.init2(node, 'template'); }

oilsRptTemplateFolderWindow.prototype.draw = function() {
	this.openWindow(DOM.oils_rpt_template_folder_window_contents_div);	
	this.fetchFolderData('template', DOM.oils_rpt_template_selector, oilsRptTemplateCache);
	var obj = this;

	DOM.oils_rpt_template_action_selector.onchange = function() {
		var action = getSelectVal(DOM.oils_rpt_template_action_selector.onchange);
		switch(action) {
			case 'create_report':
				obj.createReport();
				break;
		}
	}
}


oilsRptTemplateFolderWindow.prototype.createReport = function() {
}



oilsRptReportFolderWindow.prototype = new oilsRptFolderWindow();
oilsRptReportFolderWindow.prototype.constructor = oilsRptReportFolderWindow;
oilsRptReportFolderWindow.baseClass = oilsRptFolderWindow.prototype.constructor;
function oilsRptReportFolderWindow(node) { this.init2(node, 'report'); }

oilsRptReportFolderWindow.prototype.draw = function() {
	this.openWindow(DOM.oils_rpt_report_folder_window_contents_div);
	var obj = this;
	this.fetchFolderData('report', 
		DOM.oils_rpt_report_selector, oilsRptReportCache, 
			function() {
				appendClear(DOM.oils_rpt_report_description, 
					text(obj.getSelectedReport().description()));
			}
	);

	DOM.oils_rpt_report_folder_window_go.onclick = function() {
		var rpt = obj.getSelectedReport();
		var tmpl = oilsRptFetchTemplate(rpt.template());
		obj.oilsReport = new oilsReport( tmpl, rpt );
		var params = obj.oilsReport.gatherParams();
		obj.drawParamEditor(params);
	};
}

oilsRptReportFolderWindow.prototype.drawParamEditor = function(params) {
	_debug('drawing params: \n' + formatJSON(js2JSON(params)));
	this.drawSelectParamEditor(grep(params,
		function(p) { return (p.type == 'select')}));
	this.drawWhereParamEditor(grep(params,
		function(p) { return (p.type == 'where')}));
	this.drawHavingParamEditor(grep(params,
		function(p) { return (p.type == 'having')}));
}


var oilsRptReportFolderSelectParamRow;
oilsRptReportFolderWindow.prototype.drawSelectParamEditor = function(params) {
	if(params.length == 0) return;
	unHideMe(DOM.oils_rpt_report_folder_window_display_params_table);

	var tbody = $n(DOM.oils_rpt_report_folder_window_display_params_table,'tbody');
	if(!oilsRptReportFolderSelectParamRow)
		oilsRptReportFolderSelectParamRow = tbody.removeChild($n(tbody,'tr'));

	for( var p = 0; p < params.length; p++ ) {

		var row = oilsRptReportFolderSelectParamRow.cloneNode(true);
		var par = params[p];
		$n(row, 'column').appendChild(text(par.column.colname));
		$n(row, 'transform').appendChild(text(par.column.transform));

		if( typeof par.value == 'string' ) {
			unHideMe($n(row, 'param'));
			$n(row, 'param').value = par.value;
		} else {
			switch(par.transform) {
				case 'substring':
					unHideMe($n(row,'string_substring_widget'));
					break;
			}
		}
		tbody.appendChild(row);
	}
}

oilsRptReportFolderWindow.prototype.drawWhereParamEditor = function(params) {
}

oilsRptReportFolderWindow.prototype.drawHavingParamEditor = function(params) {
}



oilsRptReportFolderWindow.prototype.getSelectedReport = function() {
	return oilsRptReportCache[getSelectorVal(DOM.oils_rpt_report_selector)];
}

oilsRptReportFolderWindow.prototype.getSelectedAction = function() {
	return getSelectorVal(DOM.oils_rpt_report_selector, force);
}





oilsRptOutputFolderWindow.prototype = new oilsRptFolderWindow();
oilsRptOutputFolderWindow.prototype.constructor = oilsRptOutputFolderWindow;
oilsRptOutputFolderWindow.baseClass = oilsRptFolderWindow.prototype.constructor;
function oilsRptOutputFolderWindow(node) { this.init2(node, 'output'); }

oilsRptOutputFolderWindow.prototype.draw = function() {
	this.hideWindows();
	this.openWindow(null);
}




