var oilsRptID = 0;
var oilsRptID2 = 0;
var oilsRptID3 = 0;
function oilsNextId() {
	return 'oils_'+ (oilsRptID++);
}

function oilsNextNumericId() {
	return oilsRptID3++;
}

function oilsRptNextParam() {
	return '::P'+ (oilsRptID2++);
}

function oilsRptFetchOrgTree(callback) {
	var req = new Request(OILS_RPT_FETCH_ORG_TREE);
	req.callback(
		function(r) {
			globalOrgTree = r.getResultObject();
			if( callback ) callback();
		}
	);
	req.send();
}


/*
function oilsRptCacheObject(obj) {
	var id = oilsNextId();
	oilsRptObjectCache[id] = obj;
	return id;
}

function oilsRptFindObject(id) {
	return oilsRptObjectCache[id];
}
*/

function oilsRptCacheObject(type, obj, id) {
	if( !oilsRptObjectCache[type] )
		oilsRptObjectCache[type] = {};
	oilsRptObjectCache[type][id] = obj;
}

function oilsRptGetCache(type, id) {
	if( !oilsRptObjectCache[type] )
		return null;
	return oilsRptObjectCache[type][id];
}


/* -------------------------------------------- */
function oilsRptObject() {}
oilsRptObject.prototype.init = function(obj) {
	if(!obj) obj = this;
	oilsRptObject.cache(obj);
}
oilsRptObject.objectCache = {};
oilsRptObject.find = function(id) {
	return oilsRptObject.objectCache[id];
}
oilsRptObject.cache = function(obj) {
	obj.id = oilsNextNumericId();
	oilsRptObject.objectCache[obj.id] = obj;
	return obj.id;
}
/* -------------------------------------------- */


/* returns just the column name */
function oilsRptPathCol(path) {
	var parts = path.split(/-/);
	return parts.pop();
}

/* returns the IDL class of the selected column */
function oilsRptPathClass(path) {
	var parts = path.split(/-/);
	parts.pop();
	return parts.pop();
}

/* returns everything prior to the column name */
function oilsRptPathRel(path) {
	var parts = path.split(/-/);
	parts.pop();
	return parts.join('-');
}

/* creates a label "path" based on the column path */
function oilsRptMakeLabel(path) {
	var parts = path.split(/-/);
	var str = '';
	for( var i = 0; i < parts.length; i++ ) {
		if(i%2 == 0) { // IDL class names
			if( i == 0 )
				str += oilsIDL[parts[i]].label;
		} else { // Field names
            var name = parts[i];
            name = name.replace(/>.*/,''); // field name may be appended with >join-type
            var f = oilsRptFindField(oilsIDL[parts[i-1]], name);
			str += " -> "+f.label;
		}
	}
	return str;
}




function oilsRptResetParams() {
	oilsRptID2 = 0;
}

function nodeText(id) {
	if($(id))
		return $(id).innerHTML;
	return "";
}


function oilsRptDebug() {
	if(!oilsRptDebugEnabled) return;

	_debug("\n-------------------------------------\n");
	_debug(oilsRpt.toString());
	_debug("\n-------------------------------------\n");

	/*
	if(!oilsRptDebugWindow)
		oilsRptDebugWindow = window.open('','Debug','resizable,width=700,height=500,scrollbars=1,chrome'); 
	oilsRptDebugWindow.document.body.innerHTML = oilsRpt.toHTMLString();
	*/
}


function print_tabs_html(t) {
	var r = '';
	for (var j = 0; j < t; j++ ) { r = r + "&nbsp;&nbsp;"; }
	return r;
}

function formatJSONHTML(s) {
	var r = ''; var t = 0;
	for (var i in s) {
		if (s[i] == '{' || s[i] == '[') {
			r = r + s[i] + "<br/>" + print_tabs_html(++t);
		} else if (s[i] == '}' || s[i] == ']') {
			t--; r = r + "<br/>" + print_tabs_html(t) + s[i];
		} else if (s[i] == ',') {
			r = r + s[i];
			r = r + "<br/>" + print_tabs_html(t);
		} else {
			r = r + s[i];
		}
	}
	return r;
}

function setMousePos(e) {
	oilsMouseX = e.pageX
	oilsMouseY = e.pageY
	oilsPageXMid = parseInt(window.innerHeight / 2);
	oilsPageYMid = parseInt(window.innerWidth / 2);
}  

function buildFloatingDiv(div, width) {
	var left = parseInt((window.innerWidth / 2) - (width/2));
	var halfh = parseInt(div.clientHeight / 2);
	var top = oilsMouseY - halfh + 50;
	var dbot = top + halfh;
	if( dbot > window.innerHeight ) {
		top = oilsMouseY - div.clientHeight - 10;
	}
	div.setAttribute('style', 'left:'+left+'px; top:'+top+'px; width:'+width+'px');
	//div.setAttribute('style', 'top:'+top+'px;');
	//alert(DOM.oils_rpt_filter_selector.style.top);
}


function mergeObjects( src, obj ) {
	for( var i in obj ) {
		if( typeof obj[i] == 'string' ) {
			src[i] = obj[i];
		} else {
			if(src[i]) mergeObjects(src[i], obj[i]);
			else src[i] = obj[i];
		}
	}
}


/* scours the doc for elements with IDs.  When it finds one,
	it grabs the dom node and sets a reference to the node at DOM[id]; */
function oilsRptIdObjects(node) {
	if(!node) node = document.documentElement;
	if( node.nodeType != 1 ) return;
	var id = node.getAttribute('id');
	if( id ) eval("DOM."+id+"=$('"+id+"');");
	var children = node.childNodes;
	for( var c = 0; c < children.length; c++ ) 
		oilsRptIdObjects(children[c]);
}


function oilsRptObjectKeys(obj) {
	var k = [];
	for( var i in obj ) k.push(i);
	return k;
}


/* makes cls a subclass of parent */
function oilsRptSetSubClass(cls, parent) {
	var str = cls+'.prototype = new '+parent+'();\n';
	str += cls+'.prototype.constructor = '+cls+';\n';
	str += cls+'.baseClass = '+parent+'.prototype.constructor;\n';
	str += cls+'.prototype.super = '+parent+'.prototype;\n';
	eval(str);
}


function oilsRptUpdateFolder(folder, type, callback) {

	_debug("updating folder " + js2JSON(folder));

	var req = new Request(OILS_RPT_UPDATE_FOLDER, SESSION, type, folder);
	if( callback ) {
		req.callback( 
			function(r) {
				if( r.getResultObject() == 1 )
					callback(true);
				else callback(false);
			}
		);
		req.send();
	} else {
		req.send(true);
		return req.result();
	}
}

function oilsRptCreateFolder(folder, type, callback) {
	_debug("creating folder "+ js2JSON(folder));
	var req = new Request(OILS_RPT_CREATE_FOLDER, SESSION, type, folder);
	if( callback ) {
		req.callback( 
			function(r) {
				if( r.getResultObject() > 0 )
					callback(true);
				else callback(false);
			}
		);
		req.send();
	} else {
		req.send(true);
		return req.result();
	}
}

function oilsRptUpdateTemplate(template, callback) {
	oilsRptDoGenericUpdate(OILS_RPT_UPDATE_TEMPLATE, template, callback);
}

function oilsRptUpdateReport(report, callback) {
	oilsRptDoGenericUpdate(OILS_RPT_UPDATE_REPORT, report, callback);
}

function oilsRptUpdateSchedule(schedule, callback) {
	oilsRptDoGenericUpdate(OILS_RPT_UPDATE_SCHEDULE, schedule, callback);
}

function oilsRptDoGenericUpdate( method, arg, callback ) {
	_debug("generic update running: "+method);
	var req = new Request(method, SESSION, arg);
	req.callback(
		function(r) {
			if( r.getResultObject() > 0 )
				callback(true);
			else callback(false);
		}
	);
	req.send();
}

function oilsRptFetchReport(id, callback) {
	var r = oilsRptGetCache('rr', id);
	if(r) return callback(r);
	var req = new Request(OILS_RPT_FETCH_REPORT, SESSION, id);
	req.callback( 
		function(res) { 
			var rpt = res.getResultObject();
			oilsRptCacheObject('rr', rpt, id);
			callback(rpt);
		}
	);
	req.send();
}

function oilsRptFetchUser(id, callback) {
	var r = oilsRptGetCache('au', id);
	if(r) return callback(r);
	var req = new Request(FETCH_FLESHED_USER, SESSION, id, []);
	req.callback( 
		function(res) { 
			var user = res.getResultObject();
			oilsRptCacheObject('au', user, id);
			callback(user);
		}
	);
	req.send();
}

function oilsRptFetchTemplate(id, callback) {
	var t = oilsRptGetCache('rt', id);
	if(t) return callback(t);
	var r = new Request(OILS_RPT_FETCH_TEMPLATE, SESSION, id);
	r.callback( 
		function(res) { 
			var tmpl = res.getResultObject();
		oilsRptCacheObject('rt', tmpl, id);
			callback(tmpl);
		}
	);
	r.send();
}


function oilsRptAlertSuccess() { alertId('oils_rpt_generic_success'); }
function oilsRptAlertFailure() { alertId('oils_rpt_generic_failure'); }


function oilsRptBuildOutputLink(tid, rid, sid) {
	return OILS_IDL_OUTPUT_URL + tid+'/'+rid+'/'+sid+'/'+ OILS_IDL_OUTPUT_FILE;
}


