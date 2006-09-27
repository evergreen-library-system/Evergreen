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
	return '::PARAM'+ (oilsRptID2++);
}


function oilsRptCacheObject(obj) {
	var id = oilsNextId();
	oilsRptObjectCache[id] = obj;
	return id;
}

function oilsRptFindObject(id) {
	return oilsRptObjectCache[id];
}


/* -------------------------------------------- */
function oilsRptObject() {}
oilsRptObject.prototype.init = function() {
	oilsRptObject.cache(this);
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

