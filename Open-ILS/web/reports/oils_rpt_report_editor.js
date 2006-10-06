oilsRptSetSubClass('oilsRptReportEditor', 'oilsRptObject');
var oilsRptReportEditorFolderTree;

function oilsRptReportEditor(rptObject, folderWindow) {
	var tmpl = rptObject.templateObject;
	var rpt = rptObject.reportObject;
	this.folderWindow = folderWindow;

	this.template = tmpl;
	this.report = rpt;

	appendClear(DOM.oils_rpt_report_editor_template_name, tmpl.name());
	appendClear(DOM.oils_rpt_report_editor_template_creator, tmpl.owner().usrname());
	appendClear(DOM.oils_rpt_report_editor_template_description, tmpl.description());

	appendClear(DOM.oils_rpt_report_editor_cols,' | ');
	iterate(rptObject.def.select, 
		function(i) {
			DOM.oils_rpt_report_editor_cols.appendChild(text(i.alias +' | '));
		}
	);

	if( rpt ) {
		DOM.oils_rpt_report_editor_name.value = rpt.name();
		DOM.oils_rpt_report_editor_description.value = rpt.description();
	}

	this.paramEditor = new oilsRptParamEditor(
		rptObject, DOM.oils_rpt_param_editor_tbody);
	this.paramEditor.draw();

	var obj = this;
	oilsRptBuildFolder(
		'report',
		DOM.oils_rpt_report_editor_dest_folder,
		'oilsRptReportEditorFolderTree',
		'Report Folders',
		function(node) { 
			appendClear(DOM.oils_rpt_report_editor_selected_folder, node.folder.name());
			obj.selectedFolder = node; });


	oilsRptBuildFolder(
		'output',
		DOM.oils_rpt_output_dest_folder,
		'oilsRptReportEditorOutputTree',
		'Output Folders',
		function(node) { 
			appendClear(DOM.oils_rpt_output_selected_folder, node.folder.name());
			obj.selectedOutputFolder = node; });


	var obj = this;
	DOM.oils_rpt_report_editor_save.onclick = function(){obj.save();}
	DOM.oils_rpt_param_editor_sched_email.value = USER.email();
	DOM.oils_rpt_param_editor_sched_start_date.value = mkYearMonDay();
}


oilsRptReportEditor.prototype.save = function() {
	var report = new rr();

	if(!this.selectedFolder) 
		return alert('Please provide a report folder');

	report.owner( USER.id() );
	report.template( this.template.id() );
	report.folder( this.selectedFolder.folder.id() );
	report.name( DOM.oils_rpt_report_editor_name.value );
	report.description( DOM.oils_rpt_report_editor_desc.value );
	report.recur(this.paramEditor.recur());
	report.recurance(this.paramEditor.recurInterval());


	/* collect the param data */
	var data = {};
	for( var p in this.paramEditor.params ) {
		var par = this.paramEditor.params[p];
		_debug("adding report param "+par.key+" to report data");
		/*
		if( par.relWidgetChecked )
			data[par.key] = par.relWidget.getValue();
		else
		*/
		data[par.key] = par.widget.getValue();
	}

	data = js2JSON(data);
	_debug("complete report data = "+data);
	report.data(data);

	_debug("Built report:\n"+js2JSON(report));


	var time;
	if( DOM.oils_rpt_report_editor_run_now.checked ) {
		DOM.oils_rpt_report_editor_run_now.checked = false;
		time = 'now';

	} else {

		var dt = DOM.oils_rpt_param_editor_sched_start_date.value;
		if(!dt || !dt.match(/^\d{4}-\d{2}-\d{2}$/) ) {
			/* for now.. make this better in the future */
			alert('invalid start date -  YYYY-MM-DD');
			return;
		}
		var hour = getSelectorVal(DOM.oils_rpt_param_editor_sched_start_hour);
		time = dt +'T'+hour+':00';
		_debug("built run_time "+time);
	}

	if(!this.selectedOutputFolder) 
		return alert('Please provide an output folder');

	var schedule = new rs();
	schedule.folder(this.selectedOutputFolder.folder.id());
	schedule.email(DOM.oils_rpt_param_editor_sched_email.value);
	schedule.run_time(time);
	schedule.runner(USER.id());

	schedule.excel_format((DOM.oils_rpt_format_excel.checked) ? 't' : 'f');
	schedule.html_format((DOM.oils_rpt_format_html.checked) ? 't' : 'f');
	schedule.csv_format((DOM.oils_rpt_format_csv.checked) ? 't' : 'f');
	//schedule.chart_pie((DOM.oils_rpt_format_chart_pie.checked) ? 't' : 'f');
	schedule.chart_bar((DOM.oils_rpt_format_chart_bar.checked) ? 't' : 'f');
	schedule.chart_line((DOM.oils_rpt_format_chart_line.checked) ? 't' : 'f');


	debugFMObject(report);
	debugFMObject(schedule);

	//return;

	var obj = this;
	var req = new Request(OILS_RPT_CREATE_REPORT, SESSION, report, schedule );
	req.callback(
		function(r) {
			var res = r.getResultObject();
			if( res && res != '0' ) {
				oilsRptAlertSuccess();
				oilsRptCurrentFolderManager.draw();
				obj.folderWindow.draw();
			}
		}
	);
	req.send();
}


