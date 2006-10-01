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
	return oilsRptObjectCache[type][i];
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
		if(i%2 == 0) {
			if( i == 0 )
				str += oilsIDL[parts[i]].label;
		} else {
			var f = oilsRptFindField(oilsIDL[parts[i-1]], parts[i]);
			str += ":"+f.label;
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

function print_tabs(t) {
	var r = '';
	for (var j = 0; j < t; j++ ) { r = r + "  "; }
	return r;
}


function oilsRptDebug() {
	_debug("\n-------------------------------------\n");
	_debug(oilsRpt.toString());
	_debug("\n-------------------------------------\n");
	if(!oilsRptDebugEnabled) return;
	if(!oilsRptDebugWindow)
		oilsRptDebugWindow = window.open('','Debug','resizable,width=700,height=500,scrollbars=1'); 

	oilsRptDebugWindow.document.body.innerHTML = oilsRpt.toHTMLString();
}

/* pretty print JSON */
function formatJSON(s) {
	var r = ''; var t = 0;
	for (var i in s) {
		if (s[i] == '{' || s[i] == '[' ) {
			r = r + s[i] + "\n" + print_tabs(++t);
		} else if (s[i] == '}' || s[i] == ']') {
			t--; r = r + "\n" + print_tabs(t) + s[i];
		} else if (s[i] == ',') {
			r = r + s[i] + "\n" + print_tabs(t);
		} else {
			r = r + s[i];
		}
	}
	return r;
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

function oilsRptAlertSuccess() { alertId('oils_rpt_generic_success'); }

