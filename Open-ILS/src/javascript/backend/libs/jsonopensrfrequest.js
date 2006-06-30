try {
	load_lib('jsOO.js');
	load_lib('JSON.js');
} catch (e) {}

var __jsonopensrfreqid = 1;
var __jsonopensrfreq_hash = {};

function JSONOpenSRFRequest () {
        // Cache this for later ...
        this._hash_id = __jsonopensrfreqid;
        __jsonopensrfreqid++;
}

JSONOpenSRFRequest.method('create',function (service) {
        this._service = service;
        __jsonopensrfreq_hash['id' + this._hash_id] = {};
});

JSONOpenSRFRequest.method('open',function (service, method, async) {
        this._service = service;
        this._method = method;
        this._async = (async ? 1 : 0);
        __jsonopensrfreq_hash['id' + this._hash_id] = {};
});

JSONOpenSRFRequest.method('close',function () {
        this._service = null;
        this._method = null;
        this._async = null;
        __jsonopensrfreq_hash['id' + this._hash_id] = {};
});

JSONOpenSRFRequest.method('call',function (method, async) {
        this._method = method;
        this._async = (async ? 1 : 0);
});

JSONOpenSRFRequest.method('connect', function (service) {

        if (service) this._service = service;

	if (!this._service)
		throw "call .open with a service before calling .connect";
	try {
        	_OILS_FUNC_jsonopensrfrequest_connect(this._hash_id,this._service);
	} catch (e) {
		alert("Sorry, no JSONOpenSRFRequest support");
	}

        this.connected = __jsonopensrfreq_hash['id' + this._hash_id].connected;
});

JSONOpenSRFRequest.method('disconnect', function () {

	if (!this._service)
		throw "call .connect before calling .disconnect";
	try {
        	_OILS_FUNC_jsonopensrfrequest_disconnect(this._hash_id);
	} catch (e) {
		alert("Sorry, no JSONOpenSRFRequest support");
	}

        this.connected = __jsonopensrfreq_hash['id' + this._hash_id].connected;
});

JSONOpenSRFRequest.method('finish', function () {

	if (!this._service)
		throw "call .connect before calling .finish";
	try {
        	_OILS_FUNC_jsonopensrfrequest_disconnect(this._hash_id);
        	_OILS_FUNC_jsonopensrfrequest_finish(this._hash_id);
	} catch (e) {
		alert("Sorry, no JSONOpenSRFRequest support");
	}

        this.connected = __jsonopensrfreq_hash['id' + this._hash_id].connected;
});

JSONOpenSRFRequest.method('send', function () {

	if (!this._service)
		throw "call .open with a service and a method before calling .send";

	var data = [];
	for (var i = 0; i < arguments.length; i++) {
		data[i] = arguments[i];
	}

	try {
        	//log_debug( this._hash_id + " -> " + this._service + " -> " + this._method + " -> " + this._async + " -> " + js2JSON(data));
        	_OILS_FUNC_jsonopensrfrequest_send(this._hash_id,this._service,this._method,this._async,js2JSON(data));
	} catch (e) {
		alert("Sorry, no JSONOpenSRFRequest support");
	}

        this.responseText = __jsonopensrfreq_hash['id' + this._hash_id].responseText;
        this.readyState = __jsonopensrfreq_hash['id' + this._hash_id].readyState;
        this.status = __jsonopensrfreq_hash['id' + this._hash_id].status;
        this.statusText = __jsonopensrfreq_hash['id' + this._hash_id].statusText;
        this.responseJSON = JSON2js(this.responseText);

        if (this._async)
                this.onreadystatechange();
});


