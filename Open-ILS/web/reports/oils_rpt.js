var perms = [ 'RUN_REPORTS', 'SHARE_REPORT_FOLDER' ];

function oilsInitReports() {
	oilsRptIdObjects();

	/* tell FF to capture mouse movements */
	document.captureEvents(Event.MOUSEMOVE);
	document.onmousemove = setMousePos;

	DEBUGSLIM = true;

	var cgi = new CGI();
	fetchUser(cgi.param('ses'));
	DOM.oils_rpt_user.appendChild(text(USER.usrname()));

	if( cgi.param('dbg') ) oilsRptDebugEnabled = true;

	fetchHighestPermOrgs(SESSION, USER.id(), perms);
	if( PERMS.RUN_REPORTS == -1 ) {
		unHideMe(DOM.oils_rpt_permission_denied);
		hideMe(DOM.oils_rpt_tree_loading);
		return false;
	}


	oilsRptCookie = new HTTP.Cookies();
	oilsRptCurrentOrg = USER.ws_ou();
	cookieManager.write(COOKIE_SES, SESSION, -1, '/');
	cookieManager.write('ws_ou', USER.ws_ou(), -1, '/');

	oilsRptFetchOrgTree(
		function() {
			oilsLoadRptTree(
				function() {
					hideMe(DOM.oils_rpt_tree_loading); 
					unHideMe(DOM.oils_rpt_folder_table);
				}
			)
		}
	);
	return true;
}

function oilsRtpInitFolders() {
	oilsRptCurrentFolderManager = 
		new oilsRptFolderManager(DOM.oils_rpt_folder_tree_div);
	oilsRptCurrentFolderManager.draw(SESSION);
}

function oilsCleanupReports() {
	try {oilsRptDebugWindow.close();} catch(e) {}
	DOM = null;
	oilsRptObjectCache = null;
	oilsRptObject.objectCache =  null;
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
	this.reportObject = reportObj;

	if(templateObj) this.setTemplate(templateObj);

	if( reportObj ) 
		this.params = JSON2js(reportObj.data());
	if(!this.params) this.params = {};
}


oilsReport.prototype.setTemplate = function(template) {
	this.def		= JSON2js(template.data());
	this.name	= template.name();
	this.templateObject = template;
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
			path		: obj.path,
			type		: type, 
			relation : obj.relation,
			field		: field
		});
	}
}




