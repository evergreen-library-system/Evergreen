function oilsInitReports() {
	oilsRptIdObjects();

	/* tell FF to capture mouse movements */
	document.captureEvents(Event.MOUSEMOVE);
	document.onmousemove = setMousePos;

	DEBUG = 1;

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
function oilsReport(templateObj, reportObj) {
	this.def = {
		select	: [],
		from		: {},
		where		: [],
		having	: [],
		order_by : []
	};

	this.params	= {};
	this.name	= "";
	this.templateObject = templateObj;
	this.reportObject = reportObj;

	if( templateObj ) {
		this.def = JSON2js(templateObj.data());
		this.name = templateObj.name();
	}

	if( reportObj ) 
		this.params = JSON2js(reportObj.data());
	if(!this.params) this.params = {};
}

oilsReport.prototype.toString = function() {
	return formatJSON(js2JSON(this));
}

oilsReport.prototype.toHTMLString = function() {
	return formatJSONHTML(js2JSON(this));
}

oilsReport.prototype.gatherParams = function() {
	//if(oilsRptObjectKeys(this.params).length == 0) return;
	_debug("we have params: " + js2JSON(this.params));

	var params	= [];
	this._gatherParams(params, this.def.where, 'where', 'condition');
	this._gatherParams(params, this.def.having, 'having', 'condition');
	return params;
}

oilsReport.prototype._gatherParams = function(params, arr, type, field) {
	if(!arr) return;
	for( var i = 0; i < arr.length; i++ ) {

		var obj = arr[i];
		node = obj[field];
		var key; 
		var op;

		/* add select transform support */

		if( typeof node == 'string' ) {
			key = node.match(/::.*/);
		} else {
			op = oilsRptObjectKeys(node)[0];
			key = (node[op] +'').match(/::.*/);
		}

		if(!key) continue;
		key = key[0].replace(/::/,'');
		_debug("key = "+key+", param = " + this.params[key]);

		params.push( { 
			key		: key,
			op			: op,
			value		: this.params[key],
			column	: obj.column,
			type		: type, 
			relation : obj.relation,
			field		: field
		});
	}
}




