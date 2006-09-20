var oilsRptID = 0;
function oilsNextId() {
	return 'oils_'+ (oilsRptID++);
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
	//oilsRptDebugWindow;
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
	var top = oilsMouseY;
	var dbot = oilsMouseY + div.clientHeight;
	if( dbot > window.innerHeight ) {
		top = oilsMouseY - div.clientHeight - 10;
	}
	div.setAttribute('style', 'left:'+left+'px; top:'+top+'px; width:'+width+'px');
}



