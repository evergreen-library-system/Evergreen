try {
	load_lib('jsOO.js');
	load_lib('jsDOM.js');
} catch (e) {}

var __xmlhttpreqid = 1;
var __xmlhttpreq_hash = {};

function XMLHttpRequest () {
        // Cache this for later ...
        this._hash_id = __xmlhttpreqid;
        __xmlhttpreqid++;
}

XMLHttpRequest.method('open',function (method, url, async) {
        this._method = method;
        this._url = url;
        this._async = (async ? 1 : 0);
});

XMLHttpRequest.method('setRequestHeader', function (header, header_value) {
        if (!this._headers) this._headers = {}
        this._headers[header] = header_value;
});

XMLHttpRequest.method('send', function (data) {

        var headerlist = '';
        for (var i in this._headers) {
                headerlist = headerlist + '\n' + i + '|' + this._headers[i];
        }

        __xmlhttpreq_hash['id' + this._hash_id] = {};

	try {
        	_OILS_FUNC_xmlhttprequest_send(this._hash_id,this._method,this._url,this._async,headerlist,data);
	} catch (e) {
		alert("Sorry, no XMLHttpRequest support");
	}

        this.responseText = __xmlhttpreq_hash['id' + this._hash_id].responseText;
        this.readyState = __xmlhttpreq_hash['id' + this._hash_id].readyState;
        this.status = __xmlhttpreq_hash['id' + this._hash_id].status;
        this.statusText = __xmlhttpreq_hash['id' + this._hash_id].statusText;
        this.responseXML = DOMImplementation.parseString(this.responseText);

        if (this._async)
                this.onreadystatechange();
});


