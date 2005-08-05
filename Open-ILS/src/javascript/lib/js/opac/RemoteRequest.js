var XML_HTTP_GATEWAY = "gateway";
var XML_HTTP_SERVER = "gapines.org";
var XML_HTTP_MAX_TRIES = 3;

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

	var i = 2;
	this.params = ""; 

	while(i < arguments.length) {
		var object = js2JSON(arguments[i++]);
		this.params += "&param=" + encodeURIComponent(object);
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

/* constructs our XMLHTTPRequest object */
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

	return true;
}


/* define the callback we use when this request has received
	all of its data */
RemoteRequest.prototype.setCompleteCallback = function(callback) {

	if(this.cancelled) return;
	var object = this;
	var xml = this.xmlhttp;

	xml.onreadystatechange = function() {
		if( xml.readyState == 4 ) {

			try {
				if(object.cancelled) return;
				callback(object);

			} catch(E) {

				/* if we receive a communication error, retry the request up
					to XML_HTTP_MAX_TRIES attempts */
				if( instanceOf(E, EXCommunication) ) {

					if(object.sendCount >= XML_HTTP_MAX_TRIES ) {
						if(isXUL()) {
							throw object;
						} else {
							alert("Arrrgghh, Matey! Error communicating:\n" +
								 E  + "\n" + object.param_string);
						}
					} else {
						object.buildXMLRequest();
						object.send();
						return;
					}
				} else {
					/* any other exception is alerted for now */
					//RemoteRequest.prunePending(object.id);
					//alert("Exception: " + E);
					throw E;
				}

			}  finally {

				object.callback = null;
				object.xmlhttp.onreadystatechange = function(){};
				object.xmlhttp = null;
				object.params = null;
				object.param_string = null;
			}
		}
	}
}


/* http by default.  This makes it https. *ONLY works when
	embedded in a XUL app. */
RemoteRequest.prototype.setSecure = function(bool) {
	this.secure = bool; 
}

/** Send the request 
  * By default, all calls are asynchronous.  if 'blocking' is
  * set to true, then the call will block until a response
  * is received.  If blocking, callbacks will not be called.
  * In other words, you can assume the data is avaiable 
  * (getResponseObject()) as soon as the send call returns. 
  */
RemoteRequest.prototype.send = function(blocking) {

	if(this.cancelled) return;

	/* determine the xmlhttp server dynamically */
	var url = location.protocol + "//" + location.host + "/" + XML_HTTP_GATEWAY;

	if(isXUL()) {
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

	this.xmlhttp.send( data );
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
	//this.callback = null;
	if(this.cancelled) return null;

	var text = this.xmlhttp.responseText;
	var obj = JSON2js(text);

	if(obj == null) {
		return null;
	}

	if(obj.is_err) { 
		throw new EXCommunication(obj.err_msg); 
	}

	if( obj[0] != null && obj[1] == null ) 
		obj = obj[0];

	/* these are user level exceptions from the server code */
	if(instanceOf(obj, ex)) {
		/* the opac will go ahead and spit out the error msg */
		if(!isXUL()) alert(obj.err_msg());
		throw obj;
	}

	if(instanceOf(obj, perm_ex)) {
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

