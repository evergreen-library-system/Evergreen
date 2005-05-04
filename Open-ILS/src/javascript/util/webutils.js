
function hideMe(obj) {
	if(!obj)  return;
	add_css_class( obj, "hide_me");
	remove_css_class( obj, "show_me");
}

function showMe(obj) {
	if(!obj)  return;
	add_css_class( obj, "show_me");
	remove_css_class( obj, "hide_me");
}

function grabCharCode(evt) {
	evt = (evt) ? evt : ((window.event) ? event : null); /* for mozilla and IE */
	if( evt ) {
		return (evt.charCode ? evt.charCode : 
			((evt.which) ? evt.which : evt.keyCode ));
	} else { 
		return -1;
	}
}

function getById(id) {

	var obj = document.getElementById(id);
	if(obj != null) return obj;

	try {
		if(globalAppFrame) {
			obj = globalAppFrame.document.getElementById(id);
		}
	} catch(E) {
		alert("We need a globalAppFrame to function");
	}

	return obj;
}

function createAppElement(name) {
	if(globalAppFrame)
		return globalAppFrame.document.createElement(name);
	return document.createElement(name);
}

function createAppTextNode(text) {
	if(globalAppFrame)
		return globalAppFrame.document.createTextNode(text);
	return document.createTextNode(text);
}



function normalize(val) {
	var newVal = '';
	val = val.split(' ');
	for(var c=0; c < val.length; c++) {
		var string = val[c];

		for(var x = 0; x != string.length; x++) {
			if(x==0)
				newVal += string.charAt(x).toUpperCase();
			else
				newVal += string.charAt(x).toLowerCase();
		}
		if(c < (val.length-1)) newVal += " ";
	}
	return newVal;
}




var reg = /Mozilla/;
var ismoz = false;
if(reg.exec(navigator.userAgent)) 
	ismoz = true;

var DEBUG = true;

function debug(message) {
	if(DEBUG) {
		try {
			dump(" -|*|- Debug: " + message + "\n");
		} catch(E) {}
	}
}

/* finds or builds the requested row id, adding any intermediate rows along the way */
function table_row_find_or_create( table, index ) {

	if(table == null || index == null || index < 0 || index > 10000 ) {
		throw "table_row_find_or_create with invalid " +
			"params.  table: " + table + " index: " + index + "\n";
	}

	var tbody = table.getElementsByTagName("tbody")[0];

	if(tbody == null)
		tbody = table.appendChild(createAppElement("tbody"));


	if(table.rows[index] != null)
		return table.rows[index];

	var row;
	for( var x = 0; x <= index; x++ ) {
		if(table.rows[x] == null) {
			row = tbody.appendChild(createAppElement("tr"));
			//row = table.appendChild(document.createElement("tr"));
			//row = document.createElement("tr");
			//var tbody = table.getElementsByTagName("tbody")[0];
			//debug(tbody);
			//tbody.appendChild(row);
			//table.childNodes[x] = row;
			//table.rows[x] = row;
			//row = table.insertRow(x);
		}
	}
	return row;
}

/* finds or builds the requested cell,  adding any intermediate cells along the way */
function table_cell_find_or_create( row, index ) {

	if(row == null || index == null || index < 0 || index > 10000 ) {
		throw "table_cell_find_or_create with invalid " +
			"params.  row: " + row + " index: " + index + "\n";
	}

	if(row.cells[index] != null)
		return row.cells[index];

	for( var x = 0; x!= index; x++ ) {
		if(row.cells[x] == null) 
			row.insertCell(x);
	}

	return row.insertCell(index);
}
	


// -----------------------------------------------------------------------
// Generic cookie libarary copied from 
// http://webreference.com/js/column8/functions.html
// -----------------------------------------------------------------------

/*
	name - name of the cookie
   value - value of the cookie
   [expires] - expiration date of the cookie
   (defaults to end of current session)
   [path] - path for which the cookie is valid
   (defaults to path of calling document)
   [domain] - domain for which the cookie is valid
   (defaults to domain of calling document)
	[secure] - Boolean value indicating if the cookie transmission requires
	a secure transmission
   * an argument defaults when it is assigned null as a placeholder
   * a null placeholder is not required for trailing omitted arguments
	*/

function setCookie(name, value, expires, path, domain, secure) {
	var curCookie = name + "=" + escape(value) +
   ((expires) ? "; expires=" + expires.toGMTString() : "") +
   ((path) ? "; path=" + path : "") +
   ((domain) ? "; domain=" + domain : "") +
   ((secure) ? "; secure" : "");
	document.cookie = curCookie;
}


/*
	name - name of the desired cookie
   return string containing value of specified cookie or null
   if cookie does not exist
*/

function getCookie(name) {
	var dc = document.cookie;
	var prefix = name + "=";
	var begin = dc.indexOf("; " + prefix);
	if (begin == -1) {
		begin = dc.indexOf(prefix);
	   if (begin != 0) return null;
	} else {
	    begin += 2;
	}

	var end = document.cookie.indexOf(";", begin);
   if (end == -1) end = dc.length;
	return unescape(dc.substring(begin + prefix.length, end));
}


/*
	name - name of the cookie
	[path] - path of the cookie (must be same as path used to create cookie)
	[domain] - domain of the cookie (must be same as domain used to
   create cookie)
   path and domain default if assigned null or omitted if no explicit
   argument proceeds
*/

function deleteCookie(name, path, domain) {
	if (getCookie(name)) {
		var string = name + "; expires=Thu, 01-Jan-70 00:00:01 GMT";
		debug("Delete cookie string: "+ string );
		document.cookie = string;
		debug("Delete Cookie: " + document.cookie );
		/*
		document.cookie = name + "=" +
		((path) ? "; path=" + path : "") +
		((domain) ? "; domain=" + domain : "") +
		"; expires=Thu, 01-Jan-70 00:00:01 GMT";
		*/
	}
}

// date - any instance of the Date object
// * hand all instances of the Date object to this function for "repairs"

function fixDate(date) {
	var base = new Date(0);
	var skew = base.getTime();
	if (skew > 0)
		date.setTime(date.getTime() - skew);
}

// -----------------------------------------------------------------------

var globalProgressBar = null;
function ProgressBar( div, color, interval ) {

	this.progressEnd			= 9;				

	if( color != null)
		this.progressColor		= color;
	else 
		this.progressColor		= 'blue';	

	if(interval != null)
		this.progressInterval	= interval;
	else
		this.progressInterval	= 50;	

	this.progressAt = this.progressEnd;
	this.progressTimer;

	for( var x = 0; x!= this.progressEnd; x++ ) {
		var newdiv = createAppElement("span");
		newdiv.id = "progress" + x;
		newdiv.appendChild(document.createTextNode("   "));
		div.appendChild(newdiv);
	}
	globalProgressBar = this;
}

ProgressBar.prototype.progressStart = function() {
	this.progressUpdate();
}

ProgressBar.prototype.progressClear = function() {
	for (var i = 0; i < this.progressEnd; i++) {
		getById('progress' + i).style.backgroundColor = 'transparent';
	}
	progressAt = 0;
}

ProgressBar.prototype.progressUpdate = function() {
	debug(" -3-3-3-3- Updating Progress Bar");
	this.progressAt++;
	if (this.progressAt > this.progressEnd) 
		this.progressClear();
	else 
		getById('progress'+progressAt).style.backgroundColor = this.progressColor;
	this.progressTimer = setTimeout('globalProgressBar.progressUpdate()', this.progressInterval);
	debug("Timer is set at " + this.progressInterval);
}

ProgressBar.prototype.progressStop = function() {
	clearTimeout(this.progressTimer);
	this.progressClear();
}

function add_css_class(w,c) {
	var e;
	if (typeof(w) == 'object') {
		e = w;
	} else {
		e = getById(w);
	}
	var css_class_string = e.className;
	var css_class_array;

	if(css_class_string)
		css_class_array = css_class_string.split(/\s+/);

	var string_ip = ""; /*strip out nulls*/
	for (var css_class in css_class_array) {
		if (css_class_array[css_class] == c) { return; }
		if(css_class_array[css_class] !=null)
			string_ip += css_class_array[css_class] + " ";
	}
	string_ip = string_ip + c;
	e.className = string_ip;
}

function remove_css_class(w,c) {
	var e;
	if(w==null)
		return;

	if (typeof(w) == 'object') {
		e = w;
	} else {
		e = getById(w);
	}
	var css_class_string = '';

	var css_class_array = e.className;
	if( css_class_array )
		css_class_array = css_class_array.split(/\s+/);

	var first = 1;
	for (var css_class in css_class_array) {
		if (css_class_array[css_class] != c) {
			if (first == 1) {
				css_class_string = css_class_array[css_class];
				first = 0;
			} else {
				css_class_string = css_class_string + ' ' +
					css_class_array[css_class];
			}
		}
	}
	e.className = css_class_string;
}




/* takes an array of the form [ key, value, key, value, ..] and 
	redirects the page to the current host/path plus the key
	value pairs provided 
	*/
function url_redirect(key_value_array) {

	if( key_value_array == null || 
			(key_value_array.length %2))  {
		throw new EXArg( 
				"AdvancedSearchPage.redirect has invalid args" );
	}

	var fullpath = globalRootPath;
	var x = 0;

	debug("Redirecting...");

	for( var x = 0; x!= key_value_array.length; x++ ) {
		debug("Checking key_value_array " + x + " : " + key_value_array[x] );
		if( x == 0 )
			fullpath += "?" + encodeURIComponent(key_value_array[x]);
		else {
			if((x%2) == 0)
				fullpath += "&" + encodeURIComponent(key_value_array[x]);
			if((x%2) != 0)
				fullpath += "=" + encodeURIComponent(key_value_array[x]);
		}
	}

	debug("Redirecting to " + fullpath );
	globalAppFrame.location.href = fullpath;

}
	


/* 
	the paramObj contains cgi params as object attributes 
	-> paramObj.__paramName
	paramName is the name of the parameter.  the '__' is there to
	differentiate the paramName from other object attributes.
	*/
function build_param_array() {
	var paramArray = new Array();
	for( var p in paramObj ) {
		if( p.substr(0,2) == "__" ) {
			var name = p.substr(2,p.length - 1);
			paramArray.push(name)
			paramArray.push(paramObj[p])
		}
	}
	return paramArray;
}


var evtCache = new Object();
function EventListener(bool_callback, done_callback, name, usr_object) {
	this.bool_callback = bool_callback;
	this.done_callback = done_callback;
	this.interval = 100;
	this.obj = usr_object;
	this.complete = false;
	evtCache["___" + name] = this;
}


//EventListener.prototype.poll = function() {
function eventPoll(name) {
	var obj = evtCache["___" + name];
	if(obj == null)
		throw "No Listener by that name";

	obj.complete = obj.bool_callback(obj.obj);
	if(obj.complete)
		obj.done_callback(obj.obj);
	else {
		debug("Setting timeout for next poll..");
		setTimeout("eventPoll('" + name + "')", obj.interval );
	}
}

	


function swapClass(obj, class1, class2 ) {
	if( obj.className.indexOf(class1) != -1 ) {
		remove_css_class(obj, class1);
		add_css_class(obj,class2);
	} else {
		remove_css_class(obj, class2);
		add_css_class(obj,class1);
	}
}






function findPosX(obj)
{
		var curleft = 0;
			if (obj.offsetParent)
					{
								while (obj.offsetParent)
											{
															curleft += obj.offsetLeft
																			obj = obj.offsetParent;
																	}
									}
				else if (obj.x)
							curleft += obj.x;
					return curleft;
}

function findPosY(obj)
{
		var curtop = 0;
			if (obj.offsetParent)
					{
								while (obj.offsetParent)
											{
															curtop += obj.offsetTop
																			obj = obj.offsetParent;
																	}
									}
				else if (obj.y)
							curtop += obj.y;
					return curtop;
}



function getObjectHeight(obj)  {
	    var elem = obj;
		     var result = 0;
			      if (elem.offsetHeight) {
						        result = elem.offsetHeight;
								      } else if (elem.clip && elem.clip.height) {
											        result = elem.clip.height;
													      } else if (elem.style && elem.style.pixelHeight) {
																        result = elem.style.pixelHeight;
																		      }
					    return parseInt(result);
}


function getObjectWidth(obj)  {
	    var elem = obj;
		     var result = 0;
			      if (elem.offsetWidth) {
						        result = elem.offsetWidth;
								      } else if (elem.clip && elem.clip.width) {
											        result = elem.clip.width;
													      } else if (elem.style && elem.style.pixelWidth) {
																        result = elem.style.pixelWidth;
																		      }
					    return parseInt(result);
}



function getAppWindow() {
	if( globalAppFrame)
		return globalAppFrame.window;
	return window;
}

function getDocument() {
	if(globalAppFrame)
		return globalAppFrame.document;
	return document;
}

/* returns [x, y] coords of the mouse */
function getMousePos(e) {

	var posx = 0;
	var posy = 0;
	if (!e) e = getAppWindow().event;
	if (e.pageX || e.pageY) {
		posx = e.pageX;
		posy = e.pageY;
	}
	else if (e.clientX || e.clientY) {
		posx = e.clientX + getDocument().body.scrollLeft;
		posy = e.clientY + getDocument().body.scrollTop;
	}

	return [ posx, posy ];
}

function buildFunction(string) {
	return eval("new Function(" + string + ")");
}


function instanceOf(object, constructorFunction) {

	if(!IE) {
		while (object != null) {
			if (object == constructorFunction.prototype)
				return true;
			object = object.__proto__;
		}
	} else {
		while(object != null) {
			if( object instanceof constructorFunction )
				return true;
			object = object.__proto__;
		}
	}
	return false;
}

