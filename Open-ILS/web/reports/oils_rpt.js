
function oilsInitReports() {
	oilsRptIdObjects();

	/* tell FF to capture mouse movements */
	document.captureEvents(Event.MOUSEMOVE);
	document.onmousemove = setMousePos;

	var cgi = new CGI();
	fetchUser(cgi.param('ses'));
	DOM.oils_rpt_user.appendChild(text(USER.usrname()));
	oilsRptDebugEnabled = cgi.param('dbg');
}

function oilsRtpInitFolders() {
	oilsRptCurrentFolderManager = 
		new oilsRptFolderManager(DOM.oils_rpt_folder_tree_div);
	oilsRptCurrentFolderManager.draw(SESSION);
}

function oilsCleanupReports() {
	try {oilsRptDebugWindow.close();} catch(e) {}
	DOM = null;
}


/* ---------------------------------------------------------------------
	Define the report object
	--------------------------------------------------------------------- */
function oilsReport() {
	this.def = {
		select	: [],
		from		: {},
		where		: [],
		having	: [],
		order_by : []
	};
	this.params	= {};
	this.name	= ""
}

oilsReport.prototype.toString = function() {
	return formatJSON(js2JSON(this));
}

oilsReport.prototype.toHTMLString = function() {
	return formatJSONHTML(js2JSON(this));
}


