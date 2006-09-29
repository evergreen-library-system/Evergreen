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


	var obj = this;
	DOM.oils_rpt_report_editor_save.onclick = function(){obj.save();}
}


oilsRptReportEditor.prototype.save = function() {
	var report = new rr();
	report.owner( USER.id() );
	report.template( this.template.id() );
	report.folder( this.selectedFolder.folder.id() );
	report.name( DOM.oils_rpt_report_editor_name.value );
	report.description( DOM.oils_rpt_report_editor_desc.value );

	report.recur('f');
	var data = {};

	for( var p in this.paramEditor.params ) {
		var par = this.paramEditor.params[p];
		_debug("adding report param "+par.key+" to report data");
		data[par.key] = par.widget.getValue();
	}
	data = js2JSON(data);

	_debug("complete report data = "+data);
	report.data(data);

	debug("Built report:\n"+js2JSON(report));

	var req = new Request(OILS_RPT_CREATE_REPORT, SESSION, report );
	req.callback(
		function(r) {
			var res = r.getResultObject();
			oilsRptAlertSuccess();
			oilsRptCurrentFolderManager.draw();
		}
	);
	req.send();
}

