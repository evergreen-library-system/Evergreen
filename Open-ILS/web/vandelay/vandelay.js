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

var globalDivs = [
    'vl-generic-progress',
    'vl-generic-progress-with-total',
    'vl-marc-upload-div',
    'vl-queue-div'
];

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
var currentQueueId = null;

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
    for(var i = 0; i < globalDivs.length; i++) 
        dojo.style(dojo.byId(globalDivs[i]), 'display', 'none');
    dojo.style(dojo.byId(id),'display','block');
}

function runStartupCommands() {
    currentQueueId = cgi.param('qid');
    currentType = cgi.param('qtype');
    if(currentQueueId)
        return retrieveQueuedRecords(currentType, currentQueueId, handleRetrieveRecords);
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
function processSpool(key, queueId, type, onload) {
    fieldmapper.standardRequest(
        ['open-ils.vandelay', 'open-ils.vandelay.'+type+'.process_spool'],
        {   async: true,
            params: [authtoken, key, queueId],
            oncomplete : function(r) {
                var resp = r.recv().content();
                if(e = openils.Event.parse(resp)) 
                    return alert(e);
                onload();
            }
        }
    );
}

function retrieveQueuedRecords(type, queueId, onload) {
    queuedRecords = [];
    queuedRecordsMap = {};
    resetVlQueueGridLayout();
    fieldmapper.standardRequest(
        ['open-ils.vandelay', 'open-ils.vandelay.'+type+'_queue.records.retrieve.atomic'],
        {   async: true,
            params: [authtoken, queueId, {clear_marc:1}],
            /* intermittent bug in streaming, multipart requests prevents use of onreponse for now...
            onresponse: function(r) {
                var rec = r.recv().content();
                if(e = openils.Event.parse(rec))
                    return alert(e);
                queuedRecords.push(rec);
                queuedRecordsMap[rec.id()] = rec;
            },
            */
            oncomplete: function(r){
                var recs = r.recv().content();
                if(e = openils.Event.parse(recs[0]))
                    return alert(e);
                for(var i = 0; i < recs.length; i++) {
                    var rec = recs[i];
                    queuedRecords.push(rec);
                    queuedRecordsMap[rec.id()] = rec;
                }
                onload();
            }
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

    var defs = (type == 'bib') ? bibAttrDefs : authAttrDefs;
    for(var i = 0; i < defs.length; i++) {
        var attr = defs[i]
        attrMap[attr.code()] = attr.id();
        var col = {
            name:attr.description(), 
            field:'attr.' + attr.code(),
            get: getAttrValue
        };
        //if(attr.code().match(/title/i)) col.width = 'auto'; // this is hack.
        vlQueueGridLayout[0].cells[0].push(col);
    }

    vlQueueGrid.setStructure(vlQueueGridLayout);

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

var selectableGridRecords = {};
function vlQueueGridDrawSelectBox(rowIdx) {
    var data = this.grid.model.getRow(rowIdx);
    if(!data) return '';
    var domId = 'vl-record-list-selected-' +data.id;
    selectableGridRecords[domId] = data.id;
    return "<input type='checkbox' id='"+domId+"'/>";
}

function vlSelectAllGridRecords() {
    for(var id in selectableGridRecords) 
        dojo.byId(id).checked = true;
}
function vlSelectNoGridRecords() {
    for(var id in selectableGridRecords) 
        dojo.byId(id).checked = false;
}

var handleRetrieveRecords = function() {
    buildRecordGrid(currentType);
}

function vlImportSelectedRecords() {
    displayGlobalDiv('vl-generic-progress-with-total');
    var records = [];
    for(var id in selectableGridRecords) {
        if(dojo.byId(id).checked) 
            records.push(selectableGridRecords[id]);
    }
    fieldmapper.standardRequest(
        ['open-ils.vandelay', 'open-ils.vandelay.'+currentType+'_record.list.import'],
        {   async: true,
            params: [authtoken, records],
            onresponse: function(r) {
                var resp = r.recv().content();
                if(e = openils.Event.parse(resp))
                    return alert(e);
                vlControlledProgressBar.update({maximum:resp.total, progress:resp.progress});
            },
            oncomplete: function() {
                return retrieveQueuedRecords(currentType, currentQueueId, handleRetrieveRecords);
            }
        }
    );
}


/**
  * Create queue, upload MARC, process spool, load the newly created queue 
  */
function batchUpload() {
    var queueName = dijit.byId('vl-queue-name').getValue();
    currentType = dijit.byId('vl-record-type').getValue();

    var handleProcessSpool = function() {
        console.log('records uploaded and spooled');
        retrieveQueuedRecords(currentType, currentQueueId, handleRetrieveRecords);
    }

    var handleUploadMARC = function(key) {
        console.log('marc uploaded');
        processSpool(key, currentQueueId, currentType, handleProcessSpool);
    };

    var handleCreateQueue = function(queue) {
        console.log('queue created ' + queue.name());
        currentQueueId = queue.id();
        uploadMARC(handleUploadMARC);
    };

    createQueue(queueName, currentType, handleCreateQueue);
}

dojo.addOnLoad(vlInit);
