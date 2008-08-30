/* ---------------------------------------------------------------------------
# Copyright (C) 2008  Georgia Public Library Service
# Bill Erickson <erickson@esilibrary.com>
# 
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# --------------------------------------------------------------------------- */
dojo.require("dojo.parser");
dojo.require("dojo.io.iframe"); 
dojo.require("dijit.ProgressBar"); 
dojo.require("dijit.form.Button"); 
dojo.require("dijit.form.FilteringSelect"); 
dojo.require("dojo.cookie");
dojo.require("fieldmapper.Fieldmapper");
dojo.require('openils.CGI');
dojo.require('openils.User');
dojo.require('openils.Event');

var authtoken = dojo.cookie('ses') || new openils.CGI().param('ses');
var VANDELAY_URL = '/vandelay';
var bibAttrDefs = [];
var authAttrDefs = [];

/**
  * Grab initial data
  */
function vlInit() {

    // Fetch the bib and authority attribute definitions
    fieldmapper.standardRequest(
        ['open-ils.permacrud', 'open-ils.permacrud.search.vqbrad'],
        {   async: true,
            params: [authtoken, {id:{'!=':null}}],
            onresponse: function(r) {
                var def = r.recv().content(); 
                if(openils.Event.parse(def)) 
                    return alert(def);
                bibAttrDefs.push(def);
            },
        }
    );

    fieldmapper.standardRequest(
        ['open-ils.permacrud', 'open-ils.permacrud.search.vqarad'],
        {   async: true,
            params: [authtoken, {id:{'!=':null}}],
            onresponse: function(r) {
                var def = r.recv().content(); 
                if(openils.Event.parse(def)) 
                    return alert(def);
                authAttrDefs.push(def);
            }
        }
    );
}

/**
  * asynchronously upload a file of MARC records
  */
function uploadMARC(onload){
    dojo.byId('vl-ses-input').value = authtoken;
    dojo.style(dojo.byId('vl-input-td'),"display","none");
    dojo.style(dojo.byId('vl-upload-progress-span'),"display","inline"); 

    dojo.style(dojo.byId('vl-file-label'), 'display', 'none');
    dojo.style(dojo.byId('vl-file-uploading'), 'display', 'inline');

    dojo.io.iframe.send({
        url: VANDELAY_URL,
        method: "post",
        handleAs: "html",
        form: dojo.byId('vl-marc-upload-form'),
        handle: function(data,ioArgs){
            var content = data.documentElement.textContent;
            var key = content.split(/\n/)[2]; /* XXX have to strip the headers.. (why?) */
            dojo.style(dojo.byId('vl-input-td'),"display","inline");
            dojo.style(dojo.byId('vl-upload-progress-span'),"display","none");
            dojo.style(dojo.byId('vl-file-label'), 'display', 'inline');
            dojo.style(dojo.byId('vl-file-uploading'), 'display', 'none');
            onload(key);
        }
    });
}	

/**
  * Creates a new vandelay queue
  */
function createQueue(queueName, type, onload) {
    fieldmapper.standardRequest(
        ['open-ils.vandelay', 'open-ils.vandelay.'+type+'_queue.create'],
        {   async: true,
            params: [authtoken, queueName, null, type],
            oncomplete : function(r) {
                var queue = r.recv().content();
                if(e = openils.Event.parse(queue)) 
                    return alert(e);
                onload(queue);
            }
        }
    );
}

/**
  * Tells vendelay to pull a batch of records from the cache and explode them
  * out into the vandelay tables
  */
function processSpool(key, queue, type, onload) {
    fieldmapper.standardRequest(
        ['open-ils.vandelay', 'open-ils.vandelay.'+type+'.process_spool'],
        {   async: true,
            params: [authtoken, key, queue.id()],
            oncomplete : function(r) {
                var queue = r.recv().content();
                if(e = openils.Event.parse(queue)) 
                    return alert(e);
                onload();
            }
        }
    );
}

/**
  * Create queue, upload MARC, process spool, load the newly created queue 
  */
function batchUpload() {
    var queueName = dijit.byId('vl-queue-name').getValue();
    var recordType = dijit.byId('vl-record-type').getValue();

    var currentQueue = null;

    var handleProcessSpool = function() {
        alert('records uploaded and spooled');
    }

    var handleUploadMARC = function(key) {
        alert('marc uploaded');
        processSpool(key, currentQueue, recordType, handleProcessSpool);
    };

    var handleCreateQueue = function(queue) {
        alert('queue created ' + queue.name());
        currentQueue = queue;
        uploadMARC(handleUploadMARC);
    };

    createQueue(queueName, recordType, handleCreateQueue);
}
