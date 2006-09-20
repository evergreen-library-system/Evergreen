
function oilsInitReports() {
	oilsRpt = new oilsReport();
	oilsRptDisplaySelector	= $('oils_rpt_display_selector');
	oilsRptFilterSelector	= $('oils_rpt_filter_selector');

	/* tell FF to capture mouse movements */
	document.captureEvents(Event.MOUSEMOVE);
	document.onmousemove = setMousePos;

	var cgi = new CGI();
	fetchUser(cgi.param('ses'));
	$('oils_rpt_user').appendChild(text(USER.usrname()));
	oilsRptDebugEnabled = cgi.param('dbg');

	oilsDrawRptTree(
		function() { 
			hideMe($('oils_rpt_tree_loading')); 
			unHideMe($('oils_rpt_table')); 
		}
	);

}

function oilsCleanupReports() {
	if(oilsRptDebugWindow) oilsRptDebugWindow.close();
}


/* ---------------------------------------------------------------------
	Define the report object
	--------------------------------------------------------------------- */
function oilsReport() {
	this.select		= [];
	this.from		= {};
	this.where		= [];
	this.params		= {};
}

oilsReport.prototype.toString = function() {
	return formatJSON(js2JSON(this));
}

oilsReport.prototype.toHTMLString = function() {
	return formatJSONHTML(js2JSON(this));
}


