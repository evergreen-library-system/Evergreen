

function oilsRptFetchTemplate(id) {
	var t = oilsRptGetCache('rt', id);
	if(!t) {
		var r = new Request(OILS_RPT_FETCH_TEMPLATE, SESSION, id);
		r.send(true);
		t = r.result();
		oilsRptCacheObject('rt', t, id);
	}
	return t;
}



/* generic folder window class */
oilsRptSetSubClass('oilsRptFolderWindow', 'oilsRptObject');
function oilsRptFolderWindow(type, folderId) { 
	var node = oilsRptCurrentFolderManager.findNode(type, folderId);
	this.init2(node, type);
	this.selector = DOM.oils_rpt_folder_contents_selector;
}


oilsRptFolderWindow.prototype.init2 = function(node, type) {
	this.folderNode = node;
	this.type = type;
	this.init();
}


oilsRptFolderWindow.prototype.draw = function() {

	hideMe(DOM.oils_rpt_template_folder_new_report);
	unHideMe(DOM.oils_rpt_folder_table_right_td);
	hideMe(DOM.oils_rpt_folder_table_alt_td);
	this.drawFolderDetails();

	var obj = this;
	DOM.oils_rpt_folder_content_action_go.onclick = 
		function() {obj.doFolderAction()}

	this.fetchFolderData();

	var sel = DOM.oils_rpt_folder_contents_action_selector;
	for( var i = 0; i < sel.options.length; i++ ) {
		var opt = sel.options[i];
		if( opt.getAttribute('type') == this.type )
			unHideMe(opt);
		else hideMe(opt);
	}
}

oilsRptFolderWindow.prototype.doFolderAction = function() {
	var objs = this.fmTable.getSelected();
	if( objs.length == 0 ) 
		return alert('Please select an item from the list');
	var action = getSelectorVal(DOM.oils_rpt_folder_contents_action_selector);

	switch(action) {
		case 'create_report' :
			hideMe(DOM.oils_rpt_folder_table_right_td);
			unHideMe(DOM.oils_rpt_folder_table_alt_td);
			new oilsRptReportEditor(new oilsReport(objs[0]));
			break;
	}
}


oilsRptFolderWindow.prototype.drawFolderDetails = function() {
	appendClear(DOM.oils_rpt_folder_creator_label, 
		text(this.folderNode.folder.owner().usrname()));
	appendClear(DOM.oils_rpt_folder_name_label, 
		text(this.folderNode.folder.name()));
}


oilsRptFolderWindow.prototype.fetchFolderData = function(callback) {
	removeChildren(this.selector);
	var req = new Request(OILS_RPT_FETCH_FOLDER_DATA, 
		SESSION, this.type, this.folderNode.folder.id());
	var obj = this;
	req.callback(
		function(r) {
			obj.fmTable = drawFMObjectTable( 
				{ 
					dest : obj.selector, 
					obj : r.getResultObject(),
					selectCol : true,
					selectColName : 'Select Row'	
				}
			);
			//sortables_init();
			if(callback) callback();
		}
	);
	req.send();
}


/*
oilsRptTemplateFolderWindow.prototype = new oilsRptFolderWindow();
oilsRptTemplateFolderWindow.prototype.constructor = oilsRptTemplateFolderWindow;
oilsRptTemplateFolderWindow.baseClass = oilsRptFolderWindow.prototype.constructor;
function oilsRptTemplateFolderWindow(node) { this.init2(node, 'template'); }

oilsRptTemplateFolderWindow.prototype.draw = function() {
	this.openWindow();
	this.fetchFolderData('template', DOM.oils_rpt_folder_contents_selector, oilsRptTemplateCache);
	var obj = this;

	DOM.oils_rpt_template_folder_window_go.onclick = function() {
		var action = getSelectorVal(DOM.oils_rpt_template_action_selector);
		var template = getSelectorVal(DOM.oils_rpt_template_selector);
		switch(action) {
			case 'create_report':
				obj.createReport(template);
				break;
		}
	}
}


oilsRptTemplateFolderWindow.prototype.createReport = function(templateId) {
	unHideMe(DOM.oils_rpt_template_folder_new_report);
	DOM.oils_rpt_template_folder_new_report_next.onclick = function() {
		var name = DOM.oils_rpt_template_folder_new_report_name.value;
		var desc = DOM.oils_rpt_template_folder_new_report_desc.value;
		var rpt = new rr();
		rpt.template(templateId);
		rpt.name(name);
		rpt.description(desc);
		DOM.oils_rpt_template_folder_window_contents_div.appendChild(
			DOM.oils_rpt_param_editor_div);
		unHideMe(DOM.oils_rpt_param_editor_div);
		var e = new oilsRptParamEditor(
			new oilsReport(oilsRptFetchTemplate(templateId), rpt),
			DOM.oils_rpt_param_editor_tbody);
		e.draw();
	}
}



oilsRptReportFolderWindow.prototype = new oilsRptFolderWindow();
oilsRptReportFolderWindow.prototype.constructor = oilsRptReportFolderWindow;
oilsRptReportFolderWindow.baseClass = oilsRptFolderWindow.prototype.constructor;
function oilsRptReportFolderWindow(node) { this.init2(node, 'report'); }

oilsRptReportFolderWindow.prototype.draw = function() {
	this.openWindow();
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
	};
}

oilsRptReportFolderWindow.prototype.drawParamEditor = function(params) {
	_debug('drawing params: \n' + formatJSON(js2JSON(params)));
}


var oilsRptReportFolderSelectParamRow;
oilsRptReportFolderWindow.prototype.drawSelectParamEditor = function(params) {
	if(params.length == 0) return;
	//unHideMe(DOM.oils_rpt_report_folder_window_display_params_table);

	//var tbody = $n(DOM.oils_rpt_report_folder_window_display_params_table,'tbody');
	//if(!oilsRptReportFolderSelectParamRow)
		//oilsRptReportFolderSelectParamRow = tbody.removeChild($n(tbody,'tr'));
//
	//for( var p = 0; p < params.length; p++ ) {
//
		//var row = oilsRptReportFolderSelectParamRow.cloneNode(true);
		//var par = params[p];
		//$n(row, 'column').appendChild(text(par.column.colname));
		//$n(row, 'transform').appendChild(text(par.column.transform));
//
		//if( typeof par.value == 'string' ) {
			//unHideMe($n(row, 'param'));
			//$n(row, 'param').value = par.value;
		//} else {
			//switch(par.transform) {
				//case 'substring':
					//unHideMe($n(row,'string_substring_widget'));
					//break;
			//}
		//}
		//tbody.appendChild(row);
	//}
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
*/




