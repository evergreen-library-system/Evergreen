
var XML_HTTP_GATEWAY = "gateway";
var XML_HTTP_SERVER = "spacely.georgialibraries.org";
var XML_HTTP_MAX_TRIES = 3;


/* ----------------------------------------------------------------------- */
/* class methods */

RemoteRequest.pending = new Array();

RemoteRequest.prunePending = function(id) {
	var tmpArray = new Array();
	for( var x in RemoteRequest.pending ) {
		if( RemoteRequest.pending[x] != null ) {
			if( RemoteRequest.pending[x].id != id )
				tmpArray.push(RemoteRequest.pending[x]);
		}
	}
	RemoteRequest.pending = tmpArray;
	debug("Pending array has length " + RemoteRequest.pending.length );
}

RemoteRequest.numPending = function() {
	return RemoteRequest.pending.length;
}


/* ----------------------------------------------------------------------- */
/* Request object */
function RemoteRequest( service, method ) {

	this.service	= service;
	this.method		= method;
	this.xmlhttp	= false;
	this.name		= null;
	this.sendCount = 0;

	/* give us the ability to ignore responses from cancelled searches */
	//this.cancelled = false; 

	this.type		= "POST"; /* default */

	this.id			= service + method + Math.random();

	var i = 2;
	this.params = ""; 
	while(arguments[i] != null) {
		var object = js2JSON(arguments[i++]);
		this.params += "&__param=" + encodeURIComponent(object);
	}

	if(!this.params) { this.params = ""; }
	this.param_string = "service=" + service + "&method=" + method + this.params;

	if( ! this.type || ! this.service || ! this.method ) {
		alert( "ERROR IN REQUEST PARAMS");
		return null;
	}

	if( this.buildXMLRequest() == null )
		alert("NEWER BROWSER");
}

RemoteRequest.prototype.buildXMLRequest = function() {

	try { 
		this.xmlhttp = new ActiveXObject("Msxml2.XMLHTTP"); 
	} catch (e) {
		try { 
			this.xmlhttp = new ActiveXObject("Microsoft.XMLHTTP"); 
		} catch (E) {
			this.xmlhttp = false;
		}
	}

	if (!this.xmlhttp && typeof XMLHttpRequest!='undefined') {
		this.xmlhttp = new XMLHttpRequest();
	}

	if(!this.xmlhttp) {
		alert("NEEDS NEWER JAVASCRIPT for XMLHTTPRequest()");
		return null;
	}

	if( this.callback )
		this.setCompleteCallback( this.callback );

	return true;
}


/* define the callback we use when this request has received
	all of its data */
RemoteRequest.prototype.setCompleteCallback = function(callback) {

	var object = this;
	var obj = this.xmlhttp;
	this.callback = callback;

	this.xmlhttp.onreadystatechange = function() {
		if( obj.readyState == 4 ) {
			try {
				callback(object);
			} catch(E) {
				debug("Processing Error in complete callback: [" + E + "]");

				if( instanceOf(E, EXCommunication) ) {

					debug("Communication Error: [" + E + "]");
					if(object.sendCount > XML_HTTP_MAX_TRIES ) {
						alert("Arrrgghh, Matey! Error communicating:\n" +
								 E  + "\n" + object.param_string);
					} else {
						object.buildXMLRequest();
						object.send();
						return;
					}
				} else {
					RemoteRequest.prunePending(object.id);
					alert("Exception: " + E);
					throw E;
				}
			}

			RemoteRequest.prunePending(object.id);
		}
	}
}


/* http by default.  This makes it https */
RemoteRequest.prototype.setSecure = function(bool) {
	this.secure = bool; }

/** Send the request 
  * By default, all calls are asynchronous.  if 'blocking' is
  * set to true, then the call will block until a response
  * is received.  If blocking, callbacks will not be called.
  * In other words, you can assume the data is avaiable as soon as the
  * send call returns. 
  */
RemoteRequest.prototype.send = function(blocking) {

	if( this.sendCount == 0)
		RemoteRequest.pending.push(this);
	else 
		debug("Resending request with id " + this.id 
				+ " and send count " + this.sendCount);

	

	/* determine the xmlhttp server dynamically */
	var url = location.protocol + "//" + location.host + "/" + XML_HTTP_GATEWAY;

	var XUL = true;  /*will be global, needs to be set by the parent XUL app when around */
	if(XUL) {
		if(this.secure)
			url =	"https://" + XML_HTTP_SERVER + "/" + XML_HTTP_GATEWAY;
		else
			url =	"http://" + XML_HTTP_SERVER + "/" + XML_HTTP_GATEWAY;
	}

	var data = null;

	if( this.type == 'GET' ) { 
		url +=  "?" + this.param_string; 
	}

	if(blocking) {
		this.xmlhttp.open(this.type, url, false);
	} else {
		this.xmlhttp.open(this.type, url, true);
	}


	if( this.type == 'POST' ) {
		data = this.param_string;
		this.xmlhttp.setRequestHeader('Content-Type',
				'application/x-www-form-urlencoded');
	}

	//if(!this.cancelled)
	this.xmlhttp.send( data );

	this.sendCount += 1;

	return this;
}

RemoteRequest.prototype.getText = function() {
	return this.xmlhttp.responseText;
}

RemoteRequest.prototype.isReady = function() {
	return this.xmlhttp.readyState == 4;
}


RemoteRequest.prototype.getResultObject = function() {
	var text = this.xmlhttp.responseText;
	var obj = JSON2js(text);
	if(obj == null) {
		debug("received null response");
		return null;
	}

	if(obj && obj.is_err) { 
		debug("Something's Wrong: " + js2JSON(obj));
		throw new EXCommunication(obj.err_msg); 
	}

	if( obj[0] != null && obj[1] == null ) 
		return obj[0];

	return obj;
}

RemoteRequest.prototype.addParam = function(param) {
	var string = encodeURIComponent(js2JSON(param));
	this.param_string += "&__param=" + string;
}
