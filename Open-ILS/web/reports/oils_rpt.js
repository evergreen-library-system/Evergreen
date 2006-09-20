
function oilsInitReports() {
	/* tell FF to capture mouse movements */
	document.captureEvents(Event.MOUSEMOVE);
	document.onmousemove = setMousePos;

	var cgi = new CGI();
	fetchUser(cgi.param('ses'));
	$('oils_rpt_user').appendChild(text(USER.usrname()));
	oilsRptDebugEnabled = cgi.param('dbg');
}

function oilsCleanupReports() {
	try {oilsRptDebugWindow.close();} catch(e) {}
}


/* ---------------------------------------------------------------------
	Define the report object
	--------------------------------------------------------------------- */
function oilsReport() {
	this.def = {
		select	: [],
		from		: {},
		where		: []
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


