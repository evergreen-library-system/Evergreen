/* -----------------------------------------------------------------------
 * Copyright (C) 2008  Georgia Public Library Service
 * Bill Erickson <erickson@esilibrary.com>
 *  
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * ----------------------------------------------------------------------- */

var OSRF_HTTP_HEADER_TO = 'X-OpenSRF-to';
var OSRF_HTTP_HEADER_XID = 'X-OpenSRF-thread';
var OSRF_HTTP_HEADER_FROM = 'X-OpenSRF-from';
var OSRF_HTTP_HEADER_THREAD = 'X-OpenSRF-thread';
var OSRF_HTTP_HEADER_TIMEOUT = 'X-OpenSRF-timeout';
var OSRF_HTTP_HEADER_SERVICE = 'X-OpenSRF-service';
var OSRF_HTTP_HEADER_MULTIPART = 'X-OpenSRF-multipart';
var OSRF_HTTP_TRANSLATOR = '/osrf-http-translator'; /* XXX config */
var OSRF_POST_CONTENT_TYPE = 'application/x-www-form-urlencoded';


OpenSRF.XHRequest = function(osrf_msg, args) {
    this.message = osrf_msg;
    this.args = args;
    this.xreq = new XMLHttpRequest(); /* XXX browser check */
}

OpenSRF.XHRequest.prototype.send = function() {
    var xhr_req = this;
    var xreq = this.xreq

    if(this.args.timeout) {
        /* this is a standard blocking (non-multipart) call */
        xreq.open('POST', OSRF_HTTP_TRANSLATOR, false);

    } else {

        if( /* XXX browser != mozilla */ false ) {

            /* standard asynchronous call */
            xreq.onreadystatechange = function() {
                if(xreq.readyState == 4)
                    xhr_req.core_handler();
            }
            xreq.open('POST', OSRF_HTTP_TRANSLATOR, true);

        } else {

            /* asynchronous multipart call */
            xreq.multipart = true;
            xreq.onload = function(evt) {xhr_req.core_handler();}
            xreq.open('POST', OSRF_HTTP_TRANSLATOR, true);
            xreq.setRequestHeader(OSRF_HTTP_HEADER_MULTIPART, 'true');

            /* multipart requests do not pass the status info to the onload if there 
               is no new data to load.  Capture the status on the readystate handler */
            xreq.onreadystatechange = function() {
                if(xreq.readyState == 4 && xreq.status >= 400)
                    xhr_req.transport_error_handler();
            }
        }
    }

    xreq.setRequestHeader('Content-Type', OSRF_POST_CONTENT_TYPE);
    xreq.setRequestHeader(OSRF_HTTP_HEADER_THREAD, this.args.thread);
    if(this.args.rcpt)
        xreq.setRequestHeader(OSRF_HTTP_HEADER_TO, this.args.rcpt);
    else
        xreq.setRequestHeader(OSRF_HTTP_HEADER_SERVICE, this.args.rcpt_service);

    var post = 'osrf-msg=' + encodeURIComponent(js2JSON([this.message.serialize()]));
    xreq.send(post);

    if(this.args.timeout) /* this was a blocking call, manually run the handler */
        this.core_handler()

    return this;
}

OpenSRF.XHRequest.prototype.core_handler = function() {
    sender = this.xreq.getResponseHeader(OSRF_HTTP_HEADER_FROM);
    thread = this.xreq.getResponseHeader(OSRF_HTTP_HEADER_THREAD);
    json = this.xreq.responseText;
    stat = this.xreq.status;

    if(stat >= 400) 
        return this.transport_error_handler();

    OpenSRF.Stack.push(
        new OpenSRF.NetMessage(null, sender, thread, json),
        {
            onresponse : this.args.onresponse,
            oncomplete : this.args.oncomplete,
            onerror : this.args.onerror,
            onmethoderror : this.method_error_handler()
        }
    );
}


OpenSRF.XHRequest.prototype.method_error_handler = function() {
    var xhr = this;
    return function(req, status, status_text) {
        if(xhr.args.onmethoderror) 
            xhr.args.onmethoderror(req, status, status_text);
        if(xhr.args.onerror)  
            xhr.args.onerror(xhr.message, xhr.args.rcpt || xhr.args.rcpt_service, xhr.args.thread);
    }
}

OpenSRF.XHRequest.prototype.transport_error_handler = function() {
    if(this.args.ontransporterror) 
        this.args.ontransporterror(this.xreq);
    if(this.args.onerror) 
        this.args.onerror(this.message, this.args.rcpt || this.args.rcpt_service, this.args.thread);
}


