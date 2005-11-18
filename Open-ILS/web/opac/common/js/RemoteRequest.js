var XML_HTTP_GATEWAY = "gateway";
var XML_HTTP_SERVER = "dev.gapines.org";
var XML_HTTP_MAX_TRIES = 3;

//var IAMXUL = false;
function isXUL() { try { if(IAMXUL) return true;}catch(e){return false;}; }

/* some communication exceptions */
function EX(message) { this.init(message); }
EX.prototype.init = function(message) { this.message = message; }
EX.prototype.toString = function() { return "\n *** Exception Occured \n" + this.message; }  
EXCommunication.prototype              = new EX();
EXCommunication.prototype.constructor  = EXCommunication;
EXCommunication.baseClass              = EX.prototype.constructor;
function EXCommunication(message) { this.classname="EXCommunication"; this.init("EXCommunication: " + message); }                          
/* ------------------------------------------------ */


var _allrequests = {};

function cleanRemoteRequests() {
	for( var i in _allrequests ) 
		destroyRequest(_allrequests[i]);
}

function destroyRequest(r) {
	if(r == null) return;
	r.xmlhttp.onreadystatechange = function(){};
	r.xmlhttp				= null;
	r.callback				= null;
	r.userdata				= null;
	_allrequests[r.id] 	= null;
}

/* ----------------------------------------------------------------------- */
/* Request object */
function RemoteRequest( service, method ) {


	this.service	= service;
	this.method		= method;
	this.xmlhttp	= false;
	this.name		= null;
	this.sendCount = 0;

	this.type		= "POST"; /* default */
	this.id			= service + method + Math.random();
	this.cancelled = false;

	_allrequests[this.id] = this;

	var i = 2;
	this.params = ""; 

	while(i < arguments.length) {
		var object = js2JSON(arguments[i++]);
		this.params += "&param=" + encodeURIComponent(object);
	}

	if(!this.params) { this.params = ""; }
	this.param_string = "service=" + service + "&method=" + method + this.params;
	if( this.buildXMLRequest() == null ) alert("Browser is not supported!");
}

/* constructs our XMLHTTPRequest object */
RemoteRequest.prototype.buildXMLRequest = function() {

	var x;
	try { 
		x = new ActiveXObject("Msxml2.XMLHTTP"); 
	} catch (e) {
		try { 
			x = new ActiveXObject("Microsoft.XMLHTTP"); 
		} catch (E) {
			x = false;
		}
	}

	if (!x && typeof XMLHttpRequest!='undefined') x = new XMLHttpRequest();

	if(!x) {
		alert("NEEDS NEWER JAVASCRIPT for XMLHTTPRequest()");
		return null;
	}

	this.xmlhttp = x;
	return true;
}


function _remoteRequestCallback(id) {

	var object = _allrequests[id];
	if(object.cancelled) return;

	if( object.xmlhttp.readyState == 4 ) {
		try {
			object.callback(object);
		} catch(E) {

			/* if we receive a communication error, retry the request up
				to XML_HTTP_MAX_TRIES attempts */
			if( E && E.classname == "EXCommunication" ) {

				//try { dump('Communication Error: ' + E ); } catch(e){}
				alert('Debug:  Communication Error: ' + E );

				if(object.sendCount >= XML_HTTP_MAX_TRIES ) {
					if(isXUL()) throw object;
					 else alert("Arrrgghh, Matey! Error communicating:\n" + E  + "\n" + object.param_string);
				} else {
					object.buildXMLRequest();
					object.send();
					return;
				}
			} else { throw E; }

		} finally { 
			destroyRequest(object); 
			object = null; 
		}  
	}
}


/* define the callback we use when this request has received
	all of its data */
RemoteRequest.prototype.setCompleteCallback = function(callback) {
	if(this.cancelled) return;
	this.callback = callback;
	var id = this.id;
	this.xmlhttp.onreadystatechange = function() { _remoteRequestCallback(id); }
}


/* http by default.  This makes it https. *ONLY works when
	embedded in a XUL app. */
RemoteRequest.prototype.setSecure = function(bool) {
	this.secure = bool; 
}

RemoteRequest.prototype.send = function(blocking) {

	if(this.cancelled) return;

	/* determine the xmlhttp server dynamically */
	var url = location.protocol + "//" + location.host + "/" + XML_HTTP_GATEWAY;

	if(isXUL()) {
		if(this.secure || url.match(/^https:/) )
			url =	"https://" + XML_HTTP_SERVER + "/" + XML_HTTP_GATEWAY;
		else
			url =	"http://" + XML_HTTP_SERVER + "/" + XML_HTTP_GATEWAY;
	}

	var data = null;
	if( this.type == 'GET' ) url +=  "?" + this.param_string; 

	try {

		if(blocking) this.xmlhttp.open(this.type, url, false);
		else this.xmlhttp.open(this.type, url, true);
		
	} catch(E) {
		alert("Fatal error opening XMLHTTPRequest for URL:\n" + url + '\n');
		return;
	}


	if( this.type == 'POST' ) {
		data = this.param_string;
		this.xmlhttp.setRequestHeader('Content-Type',
				'application/x-www-form-urlencoded');
	}

	try{ this.xmlhttp.send( data ); } catch(e){}

	this.sendCount += 1;
	return this;
}

/* returns the actual response text from the request */
RemoteRequest.prototype.getText = function() {
	return this.xmlhttp.responseText;
}

RemoteRequest.prototype.isReady = function() {
	return this.xmlhttp.readyState == 4;
}


/* returns the JSON->js result object  */
RemoteRequest.prototype.getResultObject = function() {
	if(this.cancelled) return null;
	if(!this.xmlhttp) return null;

	var text = this.xmlhttp.responseText;
	var obj = JSON2js(text);

	if(obj == null) return null;
	if(obj.is_err)  throw new EXCommunication(obj.err_msg); 
	if( obj[0] != null && obj[1] == null ) obj = obj[0];

	/* these are user level exceptions from the server code */
	if(obj._isfieldmapper && obj.classname == "ex") {
		if(!isXUL()) alert(obj.err_msg());
		throw obj;
	}

	if(obj.__isfieldmapper && obj.classname == "perm_ex") {
		/* the opac will go ahead and spit out the error msg */
		if(!isXUL()) alert(obj.err_msg());
		throw obj;
	}

	return obj;
}

/* adds a new parameter to the request */
RemoteRequest.prototype.addParam = function(param) {
	var string = encodeURIComponent(js2JSON(param));
	this.param_string += "&param=" + string;
}

