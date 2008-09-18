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
dojo.require("dijit.layout.ContentPane");
dojo.require("dijit.layout.TabContainer");
dojo.require("dijit.Dialog");
dojo.require("dojo.cookie");
dojo.require("dojox.grid.Grid");
dojo.require("dojo.data.ItemFileReadStore");
dojo.require('dojo.date.locale');
dojo.require('dojo.date.stamp');
dojo.require("fieldmapper.Fieldmapper");
dojo.require("fieldmapper.dojoData");
dojo.require('openils.CGI');
dojo.require('openils.User');
dojo.require('openils.Event');
dojo.require('openils.MarcXPathParser');
dojo.require('openils.GridColumnPicker');

var globalDivs = [
    'vl-generic-progress',
    'vl-generic-progress-with-total',
    'vl-marc-upload-div',
    'vl-queue-div',
    'vl-match-div',
    'vl-match-html-div',
    'vl-queue-select-div',
    'vl-marc-upload-status-div'
];

var authtoken;
var VANDELAY_URL = '/vandelay-upload';
var bibAttrDefs = [];
var authAttrDefs = [];
var queuedRecords = [];
var queuedRecordsMap = {};
var bibAttrsFetched = false;
var authAttrsFetched = false;
var attrDefMap = {}; // maps attr def code names to attr def ids
var currentType;
var currentQueueId = null;
var userCache = {};
var currentMatchedRecords; // set of loaded matched bib records
var currentOverlayRecordsMap; // map of import record to overlay record
var currentImportRecId; // when analyzing matches, this is the current import record
var userBibQueues;
var userAuthQueues;
var selectableGridRecords;
var cgi = new openils.CGI();
var vlQueueGridColumePicker;

/**
  * Grab initial data
  */
function vlInit() {
    authtoken = dojo.cookie('ses') || cgi.param('ses');
    var initNeeded = 4; // how many async responses do we need before we're init'd 
    var initCount = 0; // how many async reponses we've received

    function checkInitDone() {
        initCount++;
        if(initCount == initNeeded)
            runStartupCommands();
    }

    // Fetch the bib and authority attribute definitions
    fieldmapper.standardRequest(
        ['open-ils.permacrud', 'open-ils.permacrud.search.vqbrad'],
        {   async: true,
            params: [authtoken, {id:{'!=':null}}],
            onresponse: function(r) {
                var def = r.recv().content(); 
                if(e = openils.Event.parse(def[0])) 
                    return alert(e);
                bibAttrDefs.push(def);
            },
            oncomplete: function() {
                bibAttrDefs = bibAttrDefs.sort(
                    function(a, b) {
                        if(a.id() > b.id()) return 1;
                        if(a.id() < b.id()) return -1;
                        return 0;
                    }
                );
                checkInitDone();
            }
        }
    );

    fieldmapper.standardRequest(
        ['open-ils.permacrud', 'open-ils.permacrud.search.vqarad'],
        {   async: true,
            params: [authtoken, {id:{'!=':null}}],
            onresponse: function(r) {
                var def = r.recv().content(); 
                if(e = openils.Event.parse(def[0])) 
                    return alert(e);
                authAttrDefs.push(def);
            },
            oncomplete: function() {
                authAttrDefs = authAttrDefs.sort(
                    function(a, b) {
                        if(a.id() > b.id()) return 1;
                        if(a.id() < b.id()) return -1;
                        return 0;
                    }
                );
                checkInitDone();
            }
        }
    );

    fieldmapper.standardRequest(
        ['open-ils.vandelay', 'open-ils.vandelay.bib_queue.owner.retrieve.atomic'],
        {   async: true,
            params: [authtoken],
            oncomplete: function(r) {
                var list = r.recv().content();
                if(e = openils.Event.parse(list[0]))
                    return alert(e);
                userBibQueues = list;
                checkInitDone();
            }
        }
    );

    fieldmapper.standardRequest(
        ['open-ils.vandelay', 'open-ils.vandelay.authority_queue.owner.retrieve.atomic'],
        {   async: true,
            params: [authtoken],
            oncomplete: function(r) {
                var list = r.recv().content();
                if(e = openils.Event.parse(list[0]))
                    return alert(e);
                userAuthQueues = list;
                checkInitDone();
            }
        }
    );
}

function displayGlobalDiv(id) {
    for(var i = 0; i < globalDivs.length; i++) {
        try {
            dojo.style(dojo.byId(globalDivs[i]), 'display', 'none');
        } catch(e) {
            alert('please define div ' + globalDivs[i]);
        }
    }
    dojo.style(dojo.byId(id),'display','block');
}

function runStartupCommands() {
    currentQueueId = cgi.param('qid');
    currentType = cgi.param('qtype');
    if(currentQueueId)
        return retrieveQueuedRecords(currentType, currentQueueId, handleRetrieveRecords);
    vlShowUploadForm();
}

/**
  * asynchronously upload a file of MARC records
  */
function uploadMARC(onload){
    dojo.byId('vl-ses-input').value = authtoken;
    displayGlobalDiv('vl-marc-upload-status-div');
    dojo.io.iframe.send({
        url: VANDELAY_URL,
        method: "post",
        handleAs: "html",
        form: dojo.byId('vl-marc-upload-form'),
        handle: function(data,ioArgs){
            var content = data.documentElement.textContent;
            onload(content);
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
    displayGlobalDiv('vl-generic-progress');
    queuedRecords = [];
    queuedRecordsMap = {};
    currentOverlayRecordsMap = {};
    selectableGridRecords = {};
    resetVlQueueGridLayout();

    var method = 'open-ils.vandelay.'+type+'_queue.records.retrieve.atomic';
    if(vlQueueGridShowMatches.checked)
        method = method.replace('records', 'records.matches');

    var limit = parseInt(vlQueueDisplayLimit.getValue());
    var offset = limit * parseInt(vlQueueDisplayPage.getValue()-1);

    fieldmapper.standardRequest(
        ['open-ils.vandelay', method],
        {   async: true,
            params: [authtoken, queueId, 
                {   clear_marc: 1, 
                    offset: offset,
                    limit: limit
                }
            ],
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

function vlLoadMatchUI(recId, attrCode) {
    displayGlobalDiv('vl-generic-progress');
    var matches = getRecMatchesFromAttrCode(queuedRecordsMap[recId], attrCode);
    var records = [];
    currentImportRecId = recId;
    for(var i = 0; i < matches.length; i++)
        records.push(matches[i].eg_record());

    var retrieve = ['open-ils.search', 'open-ils.search.biblio.record_entry.slim.retrieve'];
    var params = [records];
    if(currentType == 'auth') {
        retrieve = ['open-ils.cat', 'open-ils.cat.authority.record.retrieve'];
        parmas = [authtoken, records, {clear_marc:1}];
    }

    fieldmapper.standardRequest(
        retrieve,
        {   async: true,
            params:params,
            oncomplete: function(r) {
                var recs = r.recv().content();
                if(e = openils.Event.parse(recs))
                    return alert(e);

                /* ui mangling */
                displayGlobalDiv('vl-match-div');
                resetVlMatchGridLayout();
                currentMatchedRecords = recs;
                vlMatchGrid.setStructure(vlMatchGridLayout);

                // build the data store or records with match information
                var dataStore = bre.toStoreData(recs, null, {virtualFields:['field_type']});
                for(var i = 0; i < dataStore.items.length; i++) {
                    var item = dataStore.items[i];
                    for(var j = 0; j < matches.length; j++) {
                        var match = matches[j];
                        if(match.eg_record() == item.id)
                            item.field_type = match.field_type();
                    }
                }
                // now populate the grid
                vlPopulateGrid(vlMatchGrid, dataStore);
            }
        }
    );
}

function vlPopulateGrid(grid, data) {
    var store = new dojo.data.ItemFileReadStore({data:data});
    var model = new dojox.grid.data.DojoData(
        null, store, {rowsPerPage: 100, clientSort: true, query:{id:'*'}});
    grid.setModel(model);
    grid.update();
}


function vlLoadMARCHtml(recId) {
    displayGlobalDiv('vl-generic-progress');
    var api = ['open-ils.search', 'open-ils.search.biblio.record.html'];
    if(currentType == 'auth')
        api = ['open-ils.search', 'open-ils.search.authority.to_html'];
    fieldmapper.standardRequest(
        api, 
        {   async: true,
            params: [recId, 1],
            oncomplete: function(r) {
            displayGlobalDiv('vl-match-html-div');
                var html = r.recv().content();
                dojo.byId('vl-match-record-html').innerHTML = html;
            }
        }
    );
}


/**
  * Given a record, an attribute definition code, and a matching record attribute,
  * this will determine if there are any import matches and build the UI to
  * represent those matches.  If no matches exist, simply returns the attribute value
  */
function buildAttrColumnUI(rec, attrCode, attr) {
    var matches = getRecMatchesFromAttrCode(rec, attrCode);
    if(matches.length > 0) { // found some matches
        return '<div class="match_div">' +
            '<a href="javascript:void(0);" onclick="vlLoadMatchUI('+
            rec.id()+',\''+attrCode+'\');">'+ 
            attr.attr_value() + '&nbsp;('+matches.length+')</a></div>';
    }

    return attr.attr_value();
}

function getRecMatchesFromAttrCode(rec, attrCode) {
    var matches = [];
    var attr = getRecAttrFromCode(rec, attrCode);
    for(var j = 0; j < rec.matches().length; j++) {
        var match = rec.matches()[j];
        if(match.matched_attr() == attr.id()) 
            matches.push(match);
    }
    return matches;
}

function getRecAttrFromCode(rec, attrCode) {
    var defId = attrDefMap[attrCode];
    var attrs = rec.attributes();
    for(var i = 0; i < attrs.length; i++) {
        var attr = attrs[i];
        if(attr.field() == defId) 
            return attr;
    }
    return null;
}

function getAttrValue(rowIdx) {
    var data = this.grid.model.getRow(rowIdx);
    if(!data) return '';
    var attrCode = this.field.split('.')[1];
    var rec = queuedRecordsMap[data.id];
    var attr = getRecAttrFromCode(rec, attrCode);
    if(attr)
        return buildAttrColumnUI(rec, attrCode, attr);
    return '';
}

function vlGetDateTimeField(rowIdx) {
    data = this.grid.model.getRow(rowIdx);
    if(!data) return '';
    if(!data[this.field]) return '';
    var date = dojo.date.stamp.fromISOString(data[this.field]);
    return dojo.date.locale.format(date, {selector:'date'});
}

function vlGetCreator(rowIdx) {
    data = this.grid.model.getRow(rowIdx);
    if(!data) return '';
    var id = data.creator;
    if(userCache[id])
        return userCache[id].usrname();
    var user = fieldmapper.standardRequest(
        ['open-ils.actor', 'open-ils.actor.user.retrieve'], [authtoken, id]);
    if(e = openils.Event.parse(user))
        return alert(e);
    userCache[id] = user;
    return user.usrname();
}

function vlGetViewMARC(rowIdx) {
    data = this.grid.model.getRow(rowIdx);
    if(data) 
        return this.value.replace('RECID', data.id);
}

function vlGetOverlayTargetSelector(rowIdx) {
    data = this.grid.model.getRow(rowIdx);
    if(data) {
        var value = this.value.replace('ID', data.id);
        var overlay = currentOverlayRecordsMap[currentImportRecId];
        if(overlay && overlay == data.id) 
            value = value.replace('/>', 'checked="checked"/>');
        return value;
    }
}

/**
  * see if the user has enabled overlays for the current match set and, 
  * if so, map the current import record to the overlay target.
  */
function vlHandleOverlayTargetSelected() {
    if(vlOverlayTargetEnable.checked) {
        for(var i = 0; i < currentMatchedRecords.length; i++) {
            var matchRecId = currentMatchedRecords[i].id();
            if(dojo.byId('vl-overlay-target-'+matchRecId).checked) {
                console.log("found overlay target " + matchRecId);
                currentOverlayRecordsMap[currentImportRecId] = matchRecId;
                dojo.byId('vl-record-list-selected-' + currentImportRecId).checked = true;
                dojo.byId('vl-record-list-selected-' + currentImportRecId).parentNode.className = 'overlay_selected';
                return;
            }
        }
    } else {
        delete currentOverlayRecordsMap[currentImportRecId];
        dojo.byId('vl-record-list-selected-' + currentImportRecId).checked = false;
    }
}

function buildRecordGrid(type) {
    displayGlobalDiv('vl-queue-div');

    currentOverlayRecordsMap = {};

    if(queuedRecords.length == 0 && vlQueueDisplayPage.getValue() == 1) {
        dojo.style(dojo.byId('vl-queue-no-records'), 'display', 'block');
        dojo.style(dojo.byId('vl-queue-div-grid'), 'display', 'none');
        return;
    } else {
        dojo.style(dojo.byId('vl-queue-no-records'), 'display', 'none');
        dojo.style(dojo.byId('vl-queue-div-grid'), 'display', 'block');
    }

    var defs = (type == 'bib') ? bibAttrDefs : authAttrDefs;
    for(var i = 0; i < defs.length; i++) {
        var def = defs[i]
        attrDefMap[def.code()] = def.id();
        var col = {
            name:def.description(), 
            field:'attr.' + def.code(),
            get: getAttrValue,
            selectableColumn:true
        };
        //if(def.code().match(/title/i)) col.width = 'auto'; // this is hack.
        vlQueueGridLayout[0].cells[0].push(col);
    }

    var storeData;
    if(type == 'bib')
        storeData = vqbr.toStoreData(queuedRecords);
    else
        storeData = vqar.toStoreData(queuedRecords);

    var store = new dojo.data.ItemFileReadStore({data:storeData});
    var model = new dojox.grid.data.DojoData(
        null, store, {rowsPerPage: 100, clientSort: true, query:{id:'*'}});

    vlQueueGrid.setModel(model);
    if(vlQueueGridColumePicker) 
        vlQueueGrid.setStructure(vlQueueGridColumePicker.structure);
    else
        vlQueueGrid.setStructure(vlQueueGridLayout);
    vlQueueGrid.update();

    if(!vlQueueGridColumePicker) {
        vlQueueGridColumePicker = 
            new openils.GridColumnPicker(vlQueueGridColumePickerDialog, vlQueueGrid);
    }
}


function vlQueueGridDrawSelectBox(rowIdx) {
    var data = this.grid.model.getRow(rowIdx);
    if(!data) return '';
    var domId = 'vl-record-list-selected-' +data.id;
    selectableGridRecords[domId] = data.id;
    return "<div><input type='checkbox' id='"+domId+"'/></div>";
}

function vlSelectAllQueueGridRecords() {
    for(var id in selectableGridRecords) 
        dojo.byId(id).checked = true;
}
function vlSelectNoQueueGridRecords() {
    for(var id in selectableGridRecords) 
        dojo.byId(id).checked = false;
}
function vlToggleQueueGridSelect() {
    if(dojo.byId('vl-queue-grid-row-selector').checked)
        vlSelectAllQueueGridRecords();
    else
        vlSelectNoQueueGridRecords();
}

var handleRetrieveRecords = function() {
    buildRecordGrid(currentType);
}

function vlImportSelectedRecords() {
    displayGlobalDiv('vl-generic-progress-with-total');
    var records = [];

    for(var id in selectableGridRecords) {
        if(dojo.byId(id).checked) {
            var recId = selectableGridRecords[id];
            var rec = queuedRecordsMap[recId];
            if(!rec.import_time()) 
                records.push(recId);
        }
    }

    fieldmapper.standardRequest(
        ['open-ils.vandelay', 'open-ils.vandelay.'+currentType+'_record.list.import'],
        {   async: true,
            params: [authtoken, records, {overlay_map:currentOverlayRecordsMap}],
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
        dojo.style(dojo.byId('vl-upload-status-processing'), 'display', 'block');
        processSpool(key, currentQueueId, currentType, handleProcessSpool);
    };

    var handleCreateQueue = function(queue) {
        console.log('queue created ' + queue.name());
        currentQueueId = queue.id();
        uploadMARC(handleUploadMARC);
    };
    
    if(vlUploadQueueSelector.getValue() && !queueName) {
        currentQueueId = vlUploadQueueSelector.getValue();
        console.log('adding records to existing queue ' + currentQueueId);
        uploadMARC(handleUploadMARC);
    } else {
        createQueue(queueName, currentType, handleCreateQueue);
    }
}


function vlFleshQueueSelect(selector, type) {
    var data = (type == 'bib') ? vbq.toStoreData(userBibQueues) : vaq.toStoreData(userAuthQueues);
    selector.store = new dojo.data.ItemFileReadStore({data:data});
    selector.setValue(null);
    selector.setDisplayedValue('');
    if(data[0])
        selector.setValue(data[0].id());
}

function vlShowUploadForm() {
    displayGlobalDiv('vl-marc-upload-div');
    vlFleshQueueSelect(vlUploadQueueSelector, vlUploadRecordType.getValue());
}

function vlShowQueueSelect() {
    displayGlobalDiv('vl-queue-select-div');
    vlFleshQueueSelect(vlQueueSelectQueueList, vlQueueSelectType.getValue());
}

function vlFetchQueueFromForm() {
    currentType = vlQueueSelectType.getValue();
    currentQueueId = vlQueueSelectQueueList.getValue();
    retrieveQueuedRecords(currentType, currentQueueId, handleRetrieveRecords);
}

dojo.addOnLoad(vlInit);
