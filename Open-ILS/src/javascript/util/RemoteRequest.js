var XML_HTTP_URL = "https://spacely.georgialibraries.org/method/";
//var XML_HTTP_URL = "https://localhost:10444/method/";

/* Request object */
function RemoteRequest( service, method ) {

	this.service	= service;
	this.method		= method;
	this.xmlhttp	= false;
	this.name		= null;

	this.type		= "POST"; /* default */

	var i = 2;
	this.params = ""; 
	while(arguments[i] != null) {
		var object = js2JSON(arguments[i++]);
		this.params += "&__param=" + encodeURIComponent(object);
	}

	if(!this.params) { this.params = ""; }
	this.param_string = "service=" + service + "&method=" + method + this.params;
	this.url = XML_HTTP_URL;

	if( ! this.type || ! this.service || ! this.method ) {
		alert( "ERROR IN REQUEST PARAMS");
		return null;
	}

	/* try MS */
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

	var object = this;

}

/* define the callback we use when this request has received
	all of its data */
RemoteRequest.prototype.setCompleteCallback = function(callback) {
	var object = this;
	var obj = this.xmlhttp;
	this.callback = callback;
	this.xmlhttp.onreadystatechange = function() {
		if( obj.readyState == 4 ) {
			callback(object);
		}
	}
}

/** Send the request 
  * By default, all calls are asynchronous.  if 'blocking' is
  * set to true, then the call will block until a response
  * is received.  If blocking, callbacks will not be called.
  * In other, you can assume the data is avaiable as soon as the
  * send call returns. 
  */
RemoteRequest.prototype.send = function(blocking) {

	var url = this.url;
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

	this.xmlhttp.send( data );
}

RemoteRequest.prototype.getText = function() {
	return this.xmlhttp.responseText;
}

RemoteRequest.prototype.getResultObject = function() {
	var obj = JSON2js( this.xmlhttp.responseText );
	if(obj && obj.is_err) { throw new EXCommunication(obj.err_msg); }
	return obj;
}

RemoteRequest.prototype.addParam = function(param) {
	this.param_string += "&__param=" + escape(js2JSON(param));
}
