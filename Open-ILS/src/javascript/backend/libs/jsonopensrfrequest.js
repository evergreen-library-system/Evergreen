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

JSONOpenSRFRequest.method('open',function (service, method, async) {
        this._service = service;
        this._service = method;
        this._async = (async ? 1 : 0);
});

JSONOpenSRFRequest.method('send', function () {

        __jsonopensrfreq_hash['id' + this._hash_id] = {};

	try {
        	_OILS_FUNC_jsonopensrfrequest_send(this._hash_id,this._service,this._method,this._async,js2JSON(arguments));
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


