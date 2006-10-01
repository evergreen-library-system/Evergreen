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
		data[par.key] = par.widget.getValue();
	}

	data = js2JSON(data);
	_debug("complete report data = "+data);
	report.data(data);

	_debug("Built report:\n"+js2JSON(report));


	var dt = DOM.oils_rpt_param_editor_sched_start_date.value;
	if(!dt || !dt.match(/^\d{4}-\d{2}-\d{2}$/) ) {
		/* for now.. make this better in the future */
		alert('invalid start date -  YYYY-MM-DD');
		return;
	}
	var hour = getSelectorVal(DOM.oils_rpt_param_editor_sched_start_hour);
	var time = dt +'T'+hour+':00';
	_debug("built run_time "+time);

	var schedule = new rs();
	schedule.folder(this.selectedOutputFolder.folder.id());
	schedule.email(DOM.oils_rpt_param_editor_sched_email.value);
	schedule.run_time(time);

	_debug("Built schedule:\n"+js2JSON(schedule));

	var req = new Request(OILS_RPT_CREATE_REPORT, SESSION, report, schedule );
	req.callback(
		function(r) {
			var res = r.getResultObject();
			oilsRptAlertSuccess();
			oilsRptCurrentFolderManager.draw();
		}
	);
	req.send();
}


