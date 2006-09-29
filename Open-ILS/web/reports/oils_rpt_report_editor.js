oilsRptSetSubClass('oilsRptReportEditor', 'oilsRptObject');
var oilsRptReportEditorFolderTree;
function oilsRptReportEditor(rptObject) {
	var tmpl = rptObject.templateObject;
	var rpt = rptObject.reportObject;
	this.folderWindow = folderWindow;

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
		function(node) { obj.selectedFolder = node; });
}



