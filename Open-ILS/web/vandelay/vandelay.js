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
dojo.require("dojox.grid.Grid");
dojo.require("dojo.data.ItemFileReadStore");
dojo.require("fieldmapper.Fieldmapper");
dojo.require("fieldmapper.dojoData");
dojo.require('openils.CGI');
dojo.require('openils.User');
dojo.require('openils.Event');

var authtoken;
var VANDELAY_URL = '/vandelay';
var bibAttrDefs = [];
var authAttrDefs = [];
var queuedRecords = [];
var queuedRecordsMap = {};
var bibAttrsFetched = false;
var authAttrsFetched = false;
var attrMap = {};
var currentType;
var cgi = new openils.CGI();

/**
  * Grab initial data
  */
function vlInit() {
    authtoken = dojo.cookie('ses') || cgi.param('ses');
    bibAttrsFetched = false;
    authAttrsFetched = false;

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
            oncomplete: function() {
                bibAttrsFetched = true;
                if(authAttrsFetched) 
                    runStartupCommands();
            }
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
            },
            oncomplete: function() {
                authAttrsFetched = true;
                if(bibAttrsFetched) 
                    runStartupCommands();
            }
        }
    );
}

function displayGlobalDiv(id) {
    dojo.style(dojo.byId('vl-generic-progress'),"display","none");
    dojo.style(dojo.byId('vl-marc-upload-div'),"display","none");
    dojo.style(dojo.byId('vl-queue-div'),"display","none");
    dojo.style(dojo.byId(id),"display","block");
}

function runStartupCommands() {
    var queueParam = cgi.param('qid');
    currentType = cgi.param('qtype');
    if(queueParam) 
        return retrieveQueuedRecords(currentType, queueParam, handleRetrieveRecords);
    displayGlobalDiv('vl-marc-upload-div');
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

function retrieveQueuedRecords(type, queueId, onload) {
    fieldmapper.standardRequest(
        ['open-ils.vandelay', 'open-ils.vandelay.'+type+'_queue.records.retrieve'],
        {   async: true,
            params: [authtoken, queueId, {clear_marc:1}],
            onresponse: function(r) {
                var rec = r.recv().content();
                if(e = openils.Event.parse(rec))
                    return alert(e);
                queuedRecords.push(rec);
                queuedRecordsMap[rec.id()] = rec;
            },
            oncomplete: function(){onload();}
        }
    );
}

function getAttrValue(rowIdx) {
    var data = this.grid.model.getRow(rowIdx);
    if(!data) return '';
    var attrName = this.field.split('.')[1];
    var defId = attrMap[attrName];
    var rec = queuedRecordsMap[data.id];
    var attrs = rec.attributes();
    for(var i = 0; i < attrs.length; i++) {
        var attr = attrs[i];
        if(attr.field() == defId) 
            return attr.attr_value();
    }
    return '';
}

function buildRecordGrid(type) {
    displayGlobalDiv('vl-queue-div');

    /* test structure... */
    var structure = [{
        noscroll : true,
        cells : [[
            {name: 'ID', field: 'id'},
        ]]
    }];

    var defs = (type == 'bib') ? bibAttrDefs : authAttrDefs;
    for(var i = 0; i < defs.length; i++) {
        var attr = defs[i]
        attrMap[attr.code()] = attr.id();
        structure[0].cells[0].push({
            name:attr.description(), 
            field:'attr.' + attr.code(),
            get: getAttrValue
        });
    }

    vlQueueGrid.setStructure(structure);

    var storeData;
    if(type == 'bib')
        storeData = vqbr.toStoreData(queuedRecords);
    else
        storeData = vqar.toStoreData(queuedRecords);

    var store = new dojo.data.ItemFileReadStore({data:storeData});
    var model = new dojox.grid.data.DojoData(
        null, store, {rowsPerPage: 100, clientSort: true, query:{id:'*'}});
    vlQueueGrid.setModel(model);
    vlQueueGrid.update();
}

var handleRetrieveRecords = function() {
    buildRecordGrid(currentType);
}

/**
  * Create queue, upload MARC, process spool, load the newly created queue 
  */
function batchUpload() {
    var queueName = dijit.byId('vl-queue-name').getValue();
    currentType = dijit.byId('vl-record-type').getValue();
    var currentQueue = null;

    var handleProcessSpool = function() {
        console.log('records uploaded and spooled');
        retrieveQueuedRecords(currentType, currentQueue.id(), handleRetrieveRecords);
    }

    var handleUploadMARC = function(key) {
        console.log('marc uploaded');
        processSpool(key, currentQueue, currentType, handleProcessSpool);
    };

    var handleCreateQueue = function(queue) {
        console.log('queue created ' + queue.name());
        currentQueue = queue;
        uploadMARC(handleUploadMARC);
    };

    createQueue(queueName, currentType, handleCreateQueue);
}
