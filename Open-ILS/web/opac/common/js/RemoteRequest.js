var XML_HTTP_GATEWAY = "osrf-gateway-v1";
var XML_HTTP_SERVER = "";


/* This object is thrown when network failures occur */
function NetworkFailure(stat, url) { 
	this._status = stat; 
	this._url = url;
}

NetworkFailure.prototype.status = function() { return this._status; }
NetworkFailure.prototype.url = function() { return this._url; }
NetworkFailure.prototype.toString = function() { 
	return "Network Failure: status = " + this.status() +'\n'+this.url(); 
}



function isXUL() { try { if(IAMXUL) return true;}catch(e){return false;}; }
var _allrequests = {};

// If the legacy JSON gateway is needed by the staff client, uncomment this
/* 
if(isXUL()) {
    XML_HTTP_GATEWAY = 'gateway';
}
*/

function cleanRemoteRequests() {
	for( var i in _allrequests ) 
		destroyRequest(_allrequests[i]);
}

function abortAllRequests() {
	for( var i in _allrequests ) {
		var r = _allrequests[i];
		if(r) {	
			r.abort();
			destroyRequest(r);
		}
	}
}

function destroyRequest(r) {
	if(r == null) return;

	if( r.xmlhttp ) {
		r.xmlhttp.onreadystatechange = function(){};
		r.xmlhttp = null;
	}

	r.callback				= null;
	r.userdata				= null;
	_allrequests[r.id] 	= null;
}

/* ----------------------------------------------------------------------- */
/* Request object */
var rrId = 0;
function RemoteRequest( service, method ) {

	/* dojo is currently only available in the OPAC */
	try {
		/* We want OpenSRF.locale for xx-YY format */
		this.locale	= OpenSRF.locale;
	}
	catch (e) {
		this.locale = null;
	}
	this.service	= service;
	this.method		= method;
	this.xmlhttp	= false;
	this.name		= null;
	this.alertEvent = true; /* only used when isXUL is false */

	this.type		= "POST"; /* default */
	this.id			= rrId++;
	this.cancelled = false;

	this.setSecure(false);
	if(isXUL()) this.setSecure(true);

	_allrequests[this.id] = this;

	var i = 2;
	this.params = ""; 

	while(i < arguments.length) {
		var object = js2JSON(arguments[i++]);
		this.params += "&param=" + encodeURIComponent(object);
	}

	if(!this.params) { this.params = ""; }

	this.param_string = "service=" + service + "&method=" + method + this.params;
	if (this.locale != null) {
		this.param_string = this.param_string + "&locale=" + this.locale;
	}
	if( this.buildXMLRequest() == null ) alert("Browser is not supported!");

}


RemoteRequest.prototype.timeout = function(t) {
	t *= 1000
	var req = this;
	req.timeoutFunc = setTimeout(
		function() {
			if( req && req.xmlhttp ) {
				req.cancelled = true;
				req.abort();
				if( req.abtCallback ) {
					req.abtCallback(req);
				}
			}
		},
		t
	);
}

RemoteRequest.prototype.abortCallback = function(func) {
	this.abtCallback = func;
}

RemoteRequest.prototype.event = function(evt) {
	if( arguments.length > 0 )
		this.evt = evt;
	return this.evt;
}

RemoteRequest.prototype.abort = function() {
	if( this.xmlhttp ) {
		/* this has to come before abort() or IE will puke on you */
		this.xmlhttp.onreadystatechange = function(){};
		this.xmlhttp.abort();
	}
}

/* constructs our XMLHTTPRequest object */
RemoteRequest.prototype.buildXMLRequest = function() {
	this.xmlhttp = buildXMLRequest();
	return true;
}


function buildXMLRequest() {
    try {
	    return new XMLHttpRequest();
    } catch(e) {
	    try { 
		    return new ActiveXObject("Msxml2.XMLHTTP"); 
	    } catch (e2) {
		    try { 
			    return new ActiveXObject("Microsoft.XMLHTTP"); 
		    } catch (e3) {
		        alert("NEEDS NEWER JAVASCRIPT for XMLHTTPRequest()");
                return null;
		    }
	    }
    }
}


function _remoteRequestCallback(id) {

	var object = _allrequests[id];
	if(object.cancelled) return;

	if( object.xmlhttp.readyState == 4 ) {

        try {
            object.duration = new Date().getTime() - object.sendTime;
            dump('request ' + object.id + ': duration = ' + object.duration + ' ms\n');
        } catch(ee){}

		try {
			object.callback(object);
		} catch(E) {
            throw E
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
		if( XML_HTTP_SERVER ) 
			url = 'http://'+XML_HTTP_SERVER+'/'+XML_HTTP_GATEWAY;

		if( url.match(/^http:/) && 
				(this.secure || location.href.match(/^https:/) || location.href.match(/^chrome:/) || location.href.match(/^oils:/) ) ) {
			url = url.replace(/^http:/, 'https:');
		}
	}

	var data = null;
	if( this.type == 'GET' ) url +=  "?" + this.param_string; 

	this.url = url;

   //if( isXUL() ) dump('request URL = ' + url + '?' + this.param_string + '\n');

	try {

		if(blocking) this.xmlhttp.open(this.type, url, false);
		else this.xmlhttp.open(this.type, url, true);
		
	} catch(E) {
		alert("Fatal error opening XMLHTTPRequest for URL:\n" + url + '\n' + E);
		return;
	}

	if( this.type == 'POST' ) {
		data = this.param_string;
		this.xmlhttp.setRequestHeader('Content-Type',
				'application/x-www-form-urlencoded');
	}

	try {
		var auth;
		try { dojo.require('dojo.cookie'); auth = dojo.cookie(COOKIE_SES) } catch(ee) {}
		if( isXUL() ) auth = fetchXULStash().session.key;
		if( auth ) 
			this.xmlhttp.setRequestHeader('X-OILS-Authtoken', auth);

	} catch(e) {}

	if(data && data.match(/param=undefined/)) {
		/* we get a bogus param .. replace with NULL */
		try{dump('!+! UNDEFINED PARAM IN QUERY: ' + this.service + ' : ' + this.method+'\n');}catch(r){}
		data = data.replace(/param=undefined/g,'param=null');
	}


    this.sendTime = new Date().getTime();
	try{ this.xmlhttp.send( data ); } catch(e){}

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

	var failed = false;
	var status = null;
	this.event(null);

	/*
	try {
		dump(this.url + '?' + this.param_string + '\n' +
			'Returned with \n\tstatus = ' + this.xmlhttp.status + 
			'\n\tpayload= ' + this.xmlhttp.responseText + '\n');
	} catch(e) {}
	*/

	try {
		status = this.xmlhttp.status;
		if( status != 200 ) failed = true;
	} catch(e) { failed = true; }

	if( failed ) {
		if(!status) status = '<unknown>';
		try{dump('! NETWORK FAILURE.  HTTP STATUS = ' +status+'\n'+this.param_string+'\n');}catch(e){}
		if(isXUL()) 
			throw new NetworkFailure(status, this.param_string);
		else return null;
	}

	var text = this.xmlhttp.responseText;

	//try{if(getDebug()) _debug('response: ' + text + '\n')}catch(e){}

	if(text == "" || text == " " || text == null) {
		try { dump('dbg: Request returned no text!\n'); } catch(E) {}
		if(isXUL()) 
			throw new NetworkFailure(status, this.param_string);
		return null;
	}

	var obj = JSON2js(text);
	if(!obj) return null;

	if( obj.status != 200 ) {

		var str = 'A server error occurred. Debug information follows: ' +
					'\ncode = '		+ obj.status + 
					'\ndebug: '		+ obj.debug + 
					'\npayload: '	+ js2JSON(obj.payload); 

		if(isXUL()) {
			dump(str);
			throw obj;

		} else {
			_debug(str);
			throw str;
		}
	}

	var payload = obj.payload;
	if(!payload || payload.length == 0) return null;
	payload = (payload.length == 1) ? payload[0] : payload;

	if(!isXUL()) {
		if( checkILSEvent(payload) ) {
			this.event(payload);
			if( this.alertEvent ) {
				alertILSEvent(payload);
				return null;
			}
		} 
	}

	return payload;
}

/* adds a new parameter to the request */
RemoteRequest.prototype.addParam = function(param) {
	var string = encodeURIComponent(js2JSON(param));
	this.param_string += "&param=" + string;
}

function fetchXULStash() {
	if( isXUL() ) {
		try {
			var __OILS = Components.classes["@open-ils.org/openils_data_cache;1"].getService();
			return __OILS.wrappedJSObject.data;
	
		} catch(E) {
			_debug('Error in OpenILS.data._debug_stash(): ' + js2JSON(E) );
		}
	}
	return {};
}


