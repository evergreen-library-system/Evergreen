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
dojo.require("dijit.layout.LayoutContainer");
dojo.require('dijit.form.Button');
dojo.require('dijit.Toolbar');
dojo.require('dijit.Tooltip');
dojo.require('dijit.Menu');
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
    'vl-marc-html-div',
    'vl-queue-select-div',
    'vl-marc-upload-status-div',
    'vl-attr-editor-div',
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
var currentOverlayRecordsMapGid; // map of import record to overlay record grid id
var currentImportRecId; // when analyzing matches, this is the current import record
var userBibQueues = []; // only non-complete queues
var userAuthQueues = []; // only non-complete queues
var allUserBibQueues;
var allUserAuthQueues;
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
    vlFetchBibAttrDefs(function () { checkInitDone(); });
    vlFetchAuthAttrDefs(function () { checkInitDone(); });

    vlRetrieveQueueList('bib', null, 
        function(list) {
            allUserBibQueues = list;
            for(var i = 0; i < allUserBibQueues.length; i++) {
                if(allUserBibQueues[i].complete() == 'f')
                    userBibQueues.push(allUserBibQueues[i]);
            }
            checkInitDone();
        }
    );

    vlRetrieveQueueList('auth', null, 
        function(list) {
            allUserAuthQueues = list;
            for(var i = 0; i < allUserAuthQueues.length; i++) {
                if(allUserAuthQueues[i].complete() == 'f')
                    userAuthQueues.push(allUserAuthQueues[i]);
            }
            checkInitDone();
        }
    );

    vlAttrEditorInit();
}


dojo.addOnLoad(vlInit);


// fetch the bib and authority attribute definitions

function vlFetchBibAttrDefs(postcomplete) {
    bibAttrDefs = [];
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
                postcomplete();
            }
        }
    );
}

function vlFetchAuthAttrDefs(postcomplete) {
    authAttrDefs = [];
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
                postcomplete();
            }
        }
    );
}

function vlRetrieveQueueList(type, filter, onload) {
    type = (type == 'bib') ? type : 'authority';
    fieldmapper.standardRequest(
        ['open-ils.vandelay', 'open-ils.vandelay.'+type+'_queue.owner.retrieve.atomic'],
        {   async: true,
            params: [authtoken, null, filter],
            oncomplete: function(r) {
                var list = r.recv().content();
                if(e = openils.Event.parse(list[0]))
                    return alert(e);
                onload(list);
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
    dojo.style('vl-nav-bar', 'visibility', 'visible');
    if(currentQueueId)
        return retrieveQueuedRecords(currentType, currentQueueId, handleRetrieveRecords);
    vlShowUploadForm();
}

/**
  * asynchronously upload a file of MARC records
  */
function uploadMARC(onload){
    dojo.byId('vl-upload-status-count').innerHTML = '0';
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
  * Tells vandelay to pull a batch of records from the cache and explode them
  * out into the vandelay tables
  */
function processSpool(key, queueId, type, onload) {
    fieldmapper.standardRequest(
        ['open-ils.vandelay', 'open-ils.vandelay.'+type+'.process_spool'],
        {   async: true,
            params: [authtoken, key, queueId],
            onresponse : function(r) {
                var resp = r.recv().content();
                if(e = openils.Event.parse(resp)) 
                    return alert(e);
                dojo.byId('vl-upload-status-count').innerHTML = resp;
            },
            oncomplete : function(r) {onload();}
        }
    );
}

function retrieveQueuedRecords(type, queueId, onload) {
    displayGlobalDiv('vl-generic-progress');
    queuedRecords = [];
    queuedRecordsMap = {};
    currentOverlayRecordsMap = {};
    currentOverlayRecordsMapGid = {};
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

function vlLoadMatchUI(recId) {
    displayGlobalDiv('vl-generic-progress');
    var matches = queuedRecordsMap[recId].matches();
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
                if(!vlMatchGrid.structure)
                    vlMatchGrid.setStructure(vlMatchGridLayout);

                // build the data store of records with match information
                var dataStore = bre.toStoreData(recs, null, 
                    {virtualFields:['dest_matchpoint', 'src_matchpoint', '_id']});
                dataStore.identifier = '_id';

                var matchSeenMap = {};

                for(var i = 0; i < dataStore.items.length; i++) {
                    var item = dataStore.items[i];
                    item._id = i; // just need something unique
                    for(var j = 0; j < matches.length; j++) {
                        var match = matches[j];
                        if(match.eg_record() == item.id && !matchSeenMap[match.id()]) {
                            item.dest_matchpoint = match.field_type();
                            var attr = getRecAttrFromMatch(queuedRecordsMap[recId], match);
                            item.src_matchpoint = getRecAttrDefFromAttr(attr, currentType).code();
                            matchSeenMap[match.id()] = 1;
                            break;
                        }
                    }
                }

                // now populate the grid
                vlPopulateMatchGrid(vlMatchGrid, dataStore);
            }
        }
    );
}

function vlPopulateMatchGrid(grid, data) {
    var store = new dojo.data.ItemFileReadStore({data:data});
    var model = new dojox.grid.data.DojoData(
        null, store, {rowsPerPage: 100, clientSort: true, query:{id:'*'}});
    grid.setModel(model);
    grid.update();
}

function showMe(id) {
    dojo.style(dojo.byId(id), 'display', 'block');
}
function hideMe(id) {
    dojo.style(dojo.byId(id), 'display', 'none');
}


function vlLoadMARCHtml(recId, inCat, oncomplete) {
    dijit.byId('vl-marc-html-done-button').onClick = oncomplete;
    displayGlobalDiv('vl-generic-progress');
    var api;
    var params = [recId, 1];

    if(inCat) {
        hideMe('vl-marc-html-edit-button'); // don't show marc editor button
        dijit.byId('vl-marc-html-edit-button').onClick = function(){}
        api = ['open-ils.search', 'open-ils.search.biblio.record.html'];
        if(currentType == 'auth')
            api = ['open-ils.search', 'open-ils.search.authority.to_html'];
    } else {
        showMe('vl-marc-html-edit-button'); // plug in the marc editor button
        dijit.byId('vl-marc-html-edit-button').onClick = function() {vlLoadMarcEditor(currentType, recId);};
        params = [authtoken, recId];
        api = ['open-ils.vandelay', 'open-ils.vandelay.queued_bib_record.html'];
        if(currentType == 'auth')
            api = ['open-ils.vandelay', 'open-ils.vandelay.queued_authority_record.html'];
    }

    fieldmapper.standardRequest(
        api, 
        {   async: true,
            params: params,
            oncomplete: function(r) {
            displayGlobalDiv('vl-marc-html-div');
                var html = r.recv().content();
                dojo.byId('vl-marc-record-html').innerHTML = html;
            }
        }
    );
}


/*
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
*/

function getRecAttrFromMatch(rec, match) {
    for(var i = 0; i < rec.attributes().length; i++) {
        var attr = rec.attributes()[i];
        if(attr.id() == match.matched_attr())
            return attr;
    }
}

function getRecAttrDefFromAttr(attr, type) {
    var defs = (type == 'bib') ? bibAttrDefs : authAttrDefs;
    for(var i = 0; i < defs.length; i++) {
        var def = defs[i];
        if(def.id() == attr.field())
            return def;
    }
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

function vlGetViewMatches(rowIdx) {
    var data = this.grid.model.getRow(rowIdx);
    if(!data) return '';
    var rec = queuedRecordsMap[data.id];
    if(rec.matches().length > 0)
        return this.value.replace('RECID', data.id);
    return '';
}

function getAttrValue(rowIdx) {
    var data = this.grid.model.getRow(rowIdx);
    if(!data) return '';
    var attrCode = this.field.split('.')[1];
    var rec = queuedRecordsMap[data.id];
    var attr = getRecAttrFromCode(rec, attrCode);
    return (attr) ? attr.attr_value() : '';
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
        var value = this.value.replace(/GRIDID/g, data._id);
        value = value.replace(/RECID/g, currentImportRecId);
        value = value.replace(/ID/g, data.id);
        if(data._id == currentOverlayRecordsMapGid[currentImportRecId])
            return value.replace('/>', 'checked="checked"/>');
        return value;
    }
}

/**
  * see if the user has enabled overlays for the current match set and, 
  * if so, map the current import record to the overlay target.
  */
function vlHandleOverlayTargetSelected(recId, gridId) {
    var noneSelected = true;
    var checkboxes = dojo.query('[name=vl-overlay-target-'+currentImportRecId+']');
    for(var i = 0; i < checkboxes.length; i++) {
        var checkbox = checkboxes[i];
        var matchRecId = checkbox.getAttribute('match');
        var gid = checkbox.getAttribute('gridid');
        if(checkbox.checked) {
            if(matchRecId == recId && gid == gridId) {
                noneSelected = false;
                currentOverlayRecordsMap[currentImportRecId] = matchRecId;
                currentOverlayRecordsMapGid[currentImportRecId] = gid;
                dojo.byId('vl-record-list-selected-' + currentImportRecId).checked = true;
                dojo.byId('vl-record-list-selected-' + currentImportRecId).parentNode.className = 'overlay_selected';
            } else {
                checkbox.checked = false;
            }
        }
    }

    if(noneSelected) {
        delete currentOverlayRecordsMap[currentImportRecId];
        delete currentOverlayRecordsMapGid[currentImportRecId];
        dojo.byId('vl-record-list-selected-' + currentImportRecId).checked = false;
        dojo.byId('vl-record-list-selected-' + currentImportRecId).parentNode.className = '';
    }
}

var vlQueueGridBuilt = false;
function buildRecordGrid(type) {
    displayGlobalDiv('vl-queue-div');

    currentOverlayRecordsMap = {};

    if(!vlQueueGridBuilt) {
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
            vlQueueGridLayout[0].cells[0].push(col);
        }
        vlQueueGridBuilt = true;
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

    if(vlQueueGridColumePicker) {
        vlQueueGrid.update();
    } else {
        vlQueueGridColumePicker = 
            new openils.GridColumnPicker(vlQueueGridColumePickerDialog, 
                vlQueueGrid, vlQueueGridLayout, authtoken, 'vandelay.queue');
        vlQueueGridColumePicker.load();
    }
}

function vlQueueGridPrevPage() {
    var page = parseInt(vlQueueDisplayPage.getValue());
    if(page < 2) return;
    vlQueueDisplayPage.setValue(page - 1);
    retrieveQueuedRecords(currentType, currentQueueId, handleRetrieveRecords);
}

function vlQueueGridNextPage() {
    vlQueueDisplayPage.setValue(parseInt(vlQueueDisplayPage.getValue())+1);
    retrieveQueuedRecords(currentType, currentQueueId, handleRetrieveRecords);
}

function vlDeleteQueue(type, queueId, onload) {
    fieldmapper.standardRequest(
        ['open-ils.vandelay', 'open-ils.vandelay.'+type+'_queue.delete'],
        {   async: true,
            params: [authtoken, queueId],
            oncomplete: function(r) {
                var resp = r.recv().content();
                if(e = openils.Event.parse(resp))
                    return alert(e);
                onload();
            }
        }
    );
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

function vlImportRecordQueue(type, queueId, noMatchOnly, onload) {
    displayGlobalDiv('vl-generic-progress-with-total');
    var method = 'open-ils.vandelay.bib_queue.import';
    if(noMatchOnly)
        method = method.replace('import', 'nomatch.import');
    if(type == 'auth')
        method = method.replace('bib', 'auth');

    fieldmapper.standardRequest(
        ['open-ils.vandelay', method],
        {   async: true,
            params: [authtoken, queueId],
            onresponse: function(r) {
                var resp = r.recv().content();
                if(e = openils.Event.parse(resp))
                    return alert(e);
                vlControlledProgressBar.update({maximum:resp.total, progress:resp.progress});
            },
            oncomplete: function() {onload();}
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
        if(vlUploadQueueAutoImport.checked) {
            vlImportRecordQueue(currentType, currentQueueId, true,  
                function() {
                    retrieveQueuedRecords(currentType, currentQueueId, handleRetrieveRecords);
                }
            );
        } else {
            retrieveQueuedRecords(currentType, currentQueueId, handleRetrieveRecords);
        }
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
    var data = (type == 'bib') ? vbq.toStoreData(allUserBibQueues) : vaq.toStoreData(allUserAuthQueues);
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

function vlOpenMarcEditWindow(rec) {
    /*
        To run in Firefox directly, must set signed.applets.codebase_principal_support
        to true in about:config
    */
    netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect');
    win = window.open('/xul/server/cat/marcedit.xul'); // XXX version?
    win.xulG = {
        record : {marc : rec.marc()},
        save : {
            label: 'Save', // XXX
            func: function(xmlString) {
                var method = 'open-ils.permacrud.update.' + rec.classname;
                rec.marc(xmlString);
                fieldmapper.standardRequest(
                    ['open-ils.permacrud', method],
                    {   async: true,
                        params: [authtoken, rec],
                        oncomplete: function(r) {
                            if(e = openils.Event.parse(rec))
                                return alert(e);
                            alert('Record Updated'); // XXX
                            win.close();
                            // XXX reload marc html view with updates
                        }
                    }
                );
            },
        }
    };
}

function vlLoadMarcEditor(type, recId) {
    var method = 'open-ils.permacrud.search.vqbr';
    if(currentType != 'bib')
        method = method.replace(/vqbr/,'vqar');

    fieldmapper.standardRequest(
        ['open-ils.permacrud', method],
        {   async: true, 
            params: [authtoken, {id : recId}],
            oncomplete: function(r) {
                var rec = r.recv().content();
                if(e = openils.Event.parse(rec))
                    return alert(e);
                vlOpenMarcEditWindow(rec);
            }
        }
    );
}



//------------------------------------------------------------
// attribute editors

// attribute-editor global variables

var ATTR_EDITOR_IN_UPDATE_MODE = false;	// true on 'edit', false on 'create'
var ATTR_EDIT_ID = null;		// id of current 'edit' attribute
var ATTR_EDIT_GROUP = 'bib';		// bib-attrs or auth-attrs

function vlAttrEditorInit() {
    // set up tooltips on the edit form
    connectTooltip('attr-editor-tags'); 
    connectTooltip('attr-editor-subfields'); 
}

function vlShowAttrEditor() {
    displayGlobalDiv('vl-attr-editor-div');
    loadAttrEditorGrid();
    idHide('vl-generic-progress');
}

function setAttrEditorGroup(groupName) {
    // put us into 'bib'-attr or 'auth'-attr mode.
    if (ATTR_EDIT_GROUP != groupName) {
	ATTR_EDIT_GROUP = groupName;
	loadAttrEditorGrid();
    }
}

function onAttrEditorOpen() {
    // the "bars" have the create/update/cancel/etc. buttons.
    var create_bar = document.getElementById('attr-editor-create-bar');
    var update_bar = document.getElementById('attr-editor-update-bar');
    if (ATTR_EDITOR_IN_UPDATE_MODE) {
	update_bar.style.display='table-row';
	create_bar.style.display='none';
	// hide the dropdown-button
	idStyle('vl-create-attr-editor-button', 'visibility', 'hidden');
    } else {
	dijit.byId('attr-editor-dialog').reset();
	create_bar.style.display='table-row';
	update_bar.style.display='none';
    }
}

function onAttrEditorClose() {
    // reset the form to a "create" form. (We may have borrowed it for editing.)
    ATTR_EDITOR_IN_UPDATE_MODE = false;
    // show the dropdown-button
    idStyle('vl-create-attr-editor-button', 'visibility', 'visible');
}

function loadAttrEditorGrid() {
    var _data = (ATTR_EDIT_GROUP == 'auth') ? 
	vqarad.toStoreData(authAttrDefs) : vqbrad.toStoreData(bibAttrDefs) ;
		 
    var store = new dojo.data.ItemFileReadStore({data:_data});
    var model = new dojox.grid.data.DojoData(
        null, store, {rowsPerPage: 100, clientSort: true, query:{id:'*'}});
    attrEditorGrid.setModel(model);
    attrEditorGrid.setStructure(vlAttrGridLayout);
    attrEditorGrid.onRowClick = onAttrEditorClick;
    attrEditorGrid.update();
}

function attrGridGetTag(n) {
    // grid helper: return the tags from the row's xpath column.
    var xp = this.grid.model.getRow(n);
    return xp && xpathParser.parse(xp.xpath).tags;
}

function attrGridGetSubfield(n) {
    // grid helper: return the subfields from the row's xpath column.
    var xp = this.grid.model.getRow(n);
    return xp && xpathParser.parse(xp.xpath).subfields;
}

function onAttrEditorClick(evt) {
    var row = attrEditorGrid.model.getRow(evt.rowIndex);
    ATTR_EDIT_ID = row.id;
    ATTR_EDITOR_IN_UPDATE_MODE = true;

    // populate the popup editor.
    dojo.byId('attr-editor-code').value = row.code;
    dojo.byId('attr-editor-description').value = row.description;
    var parsed_xpath = xpathParser.parse(row.xpath);
    dojo.byId('attr-editor-tags').value = parsed_xpath.tags;
    dojo.byId('attr-editor-subfields').value = parsed_xpath.subfields;
    dojo.byId('attr-editor-identifier').value = (row.ident ? 'True':'False');
    dojo.byId('attr-editor-xpath').value = row.xpath;
    dojo.byId('attr-editor-remove').value = row.remove;

    // set up UI for editing
    dojo.byId('vl-create-attr-editor-button').click();
}

function vlSaveAttrDefinition(data) {
    idHide('vl-attr-editor-div');
    idShow('vl-generic-progress');

    data.id = ATTR_EDIT_ID;

    // this ought to honour custom xpaths, but overwrite xpaths
    // derived from tags/subfields.
    if (data.xpath == '' || looksLikeDerivedXpath(data.xpath)) {
	var _xpath = tagAndSubFieldsToXpath(data.tag, data.subfield);
	data.xpath = _xpath;
    }

    // build up our permacrud params. Key variables here are
    // "create or update" and "bib or auth".

    var isAuth   = (ATTR_EDIT_GROUP == 'auth');
    var isCreate = (ATTR_EDIT_ID == null);
    var rad      = isAuth ? new vqarad() : new vqbrad() ;
    var method   = 'open-ils.permacrud' + (isCreate ? '.create.' : '.update.') 
	+ (isAuth ? 'vqarad' : 'vqbrad');
    var _data    = rad.fromStoreItem(data);

    _data.ischanged(1);

    fieldmapper.standardRequest(
        ['open-ils.permacrud', method],
        {   async: true,
            params: [authtoken, _data ],
	    onresponse: function(r) { },
            oncomplete: function(r) {
		attrEditorFetchAttrDefs(vlShowAttrEditor);
		ATTR_EDIT_ID = null;
	    },
	    onerror: function(r) {
		alert('vlSaveAttrDefinition comms error: ' + r);
	    }
        }
    );
}

function attrEditorFetchAttrDefs(callback) {
    var fn = (ATTR_EDIT_GROUP == 'auth') ? vlFetchAuthAttrDefs : vlFetchBibAttrDefs;
    return fn(callback);
}

function vlAttrDelete() {
    idHide('vl-attr-editor-div');
    idShow('vl-generic-progress');

    var isAuth = (ATTR_EDIT_GROUP == 'auth');
    var method = 'open-ils.permacrud.delete.' + (isAuth ? 'vqarad' : 'vqbrad');
    var rad    = isAuth ? new vqarad() : new vqbrad() ;
    fieldmapper.standardRequest(
        ['open-ils.permacrud', method],
        {   async: true,
	    params: [authtoken, rad.fromHash({ id : ATTR_EDIT_ID }), ],
	    oncomplete: function() {
		dijit.byId('attr-editor-dialog').onCancel(); // close the dialog
		attrEditorFetchAttrDefs(vlShowAttrEditor);
		ATTR_EDIT_ID = null;
	    },
	    onerror: function(r) {
		alert('vlAttrDelete comms error: ' + r);
	    }
        }
    );
}

// ------------------------------------------------------------
// utilities for attribute editors

// dom utilities (maybe dojo does these, and these should be replaced)

function idStyle(obId, k, v)	{ document.getElementById(obId).style[k] = v;	}
function idShow(obId)		{ idStyle(obId, 'display', 'block');		}
function idHide(obId)		{ idStyle(obId, 'display' , 'none');		}

function connectTooltip(fieldId) {
    // Given an element id, look up a tooltip element in the doc (same
    // id with a '-tip' suffix) and associate the two. Maybe dojo has
    // a better way to do this?
    var fld = dojo.byId(fieldId);
    var tip = dojo.byId(fieldId + '-tip');
    dojo.connect(fld, 'onfocus', function(evt) {
		     dijit.showTooltip(tip.innerHTML, fld, ['below', 'after']); });
    dojo.connect(fld, 'onblur', function(evt) { dijit.hideTooltip(fld); });
}

// xpath utilities

var xpathParser = new openils.MarcXPathParser();

function tagAndSubFieldsToXpath(tags, subfields) {
    // given tags, and subfields, build up an XPath.
    try {
	var parts = {
	    'tags':tags.match(/[\d]+/g), 
	    'subfields':subfields.match(/[a-zA-z]/g) };
	return xpathParser.compile(parts);
    } catch (err) {
	return {'parts':null, 'tags':null, 'error':err};
    }
}

function looksLikeDerivedXpath(path) {
    // Does this path look like it was derived from tags and subfields?
    var parsed = xpathParser.parse(path);
    if (parsed.tags == null) 
	return false;
    var compiled = xpathParser.compile(parsed);
    return (path == compiled);
}

// amazing xpath-util unit-tests
if (!looksLikeDerivedXpath('//*[@tag="901"]/*[@code="c"]'))	alert('vandelay xpath-utility error');
if ( looksLikeDerivedXpath('ba-boo-ba-boo!'))			alert('vandelay xpath-utility error');
